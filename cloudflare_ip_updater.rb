#!/usr/bin/env ruby
# Copyright (c) 2025 - 2026 Jory A. Pratt, W5GLE <geekypenguin@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'net/http'
require 'json'
require 'fileutils'

class CloudflareIPUpdater
  CONFIG_FILE = '/etc/cloudflare-ip-updater/config'
  CLOUDFLARE_API_URL = 'https://api.cloudflare.com/client/v4'
  IP_STORAGE_FILE = '/var/lib/cloudflare-ip-updater/last_ip.txt'

  # Services to check external IP
  IP_CHECK_SERVICES = [
    'https://api.ipify.org?format=json',
    'https://ifconfig.me/all.json',
    'https://api.myip.com'
  ]

  attr_reader :api_token, :zone_id, :dns_record_id, :dns_record_name, :dns_record_type, :domain

  def initialize
    load_config
    validate_config
    ensure_ip_storage_directory
    resolve_zone_id if @zone_id.empty?
    resolve_dns_record_id if @dns_record_id.empty?
  end

  def load_config
    unless File.exist?(CONFIG_FILE)
      raise "Configuration file not found: #{CONFIG_FILE}"
    end

    config = {}
    File.readlines(CONFIG_FILE).each do |line|
      line = line.strip
      next if line.empty? || line.start_with?('#')
      
      key, value = line.split('=', 2)
      next unless key && value
      
      key = key.strip
      value = value.strip.gsub(/^["']|["']$/, '')  # Remove quotes
      config[key] = value
    end

    @api_token = config['CLOUDFLARE_API_TOKEN'] || ENV['CLOUDFLARE_API_TOKEN'] || ''
    @zone_id = config['CLOUDFLARE_ZONE_ID'] || ENV['CLOUDFLARE_ZONE_ID'] || ''
    @dns_record_id = config['CLOUDFLARE_DNS_RECORD_ID'] || ENV['CLOUDFLARE_DNS_RECORD_ID'] || ''
    @domain = config['DOMAIN'] || ENV['DOMAIN'] || ''
    @dns_record_name = config['DNS_RECORD_NAME'] || ENV['DNS_RECORD_NAME'] || '@'
    @dns_record_type = config['DNS_RECORD_TYPE'] || ENV['DNS_RECORD_TYPE'] || 'A'
  end

  def validate_config
    if @api_token.empty?
      raise "CLOUDFLARE_API_TOKEN must be set in #{CONFIG_FILE}"
    end
    if @domain.empty?
      raise "DOMAIN must be set in #{CONFIG_FILE}"
    end
  end

  def ensure_ip_storage_directory
    dir = File.dirname(IP_STORAGE_FILE)
    FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
  end

  def get_external_ip
    IP_CHECK_SERVICES.each do |service_url|
      begin
        uri = URI(service_url)
        response = Net::HTTP.get_response(uri)
        
        if response.code == '200'
          data = JSON.parse(response.body)
          # Different services return IP in different formats
          ip = data['ip'] || data['ip_addr'] || data['IP']
          if ip && ip.match?(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)
            puts "Current external IP: #{ip} (from #{service_url})"
            return ip
          end
        end
      rescue => e
        puts "Failed to get IP from #{service_url}: #{e.message}"
        next
      end
    end
    
    raise "Unable to determine external IP from any service"
  end

  def get_last_known_ip
    return nil unless File.exist?(IP_STORAGE_FILE)
    ip = File.read(IP_STORAGE_FILE).strip
    ip.match?(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) ? ip : nil
  rescue => e
    puts "Error reading last IP: #{e.message}"
    nil
  end

  def save_ip(ip)
    File.write(IP_STORAGE_FILE, ip)
  end

  def make_api_request(method, path, body = nil)
    uri = URI("#{CLOUDFLARE_API_URL}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request_class = case method.upcase
                    when 'GET' then Net::HTTP::Get
                    when 'PUT' then Net::HTTP::Put
                    when 'POST' then Net::HTTP::Post
                    else Net::HTTP::Get
                    end

    request = request_class.new(uri)
    request['Authorization'] = "Bearer #{@api_token}"
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'
    request.body = body.to_json if body

    response = http.request(request)
    result = JSON.parse(response.body) if response.body && !response.body.empty?

    if response.code.to_i >= 200 && response.code.to_i < 300
      result
    else
      error_msg = result && result['errors'] ? result['errors'].map { |e| e['message'] }.join(', ') : response.body
      raise "Cloudflare API error (#{response.code}): #{error_msg}"
    end
  end

  def resolve_zone_id
    puts "Looking up Zone ID for domain: #{@domain}"
    result = make_api_request('GET', "/zones?name=#{@domain}")
    
    if result['result'] && result['result'].any?
      @zone_id = result['result'].first['id']
      puts "Found Zone ID: #{@zone_id}"
    else
      raise "Domain #{@domain} not found in Cloudflare account"
    end
  end

  def resolve_dns_record_id
    record_name = @dns_record_name == '@' ? @domain : "#{@dns_record_name}.#{@domain}"
    puts "Looking up DNS Record ID for: #{record_name} (#{@dns_record_type})"
    
    result = make_api_request('GET', "/zones/#{@zone_id}/dns_records?type=#{@dns_record_type}&name=#{record_name}")
    
    if result['result'] && result['result'].any?
      @dns_record_id = result['result'].first['id']
      puts "Found DNS Record ID: #{@dns_record_id}"
    else
      raise "DNS record #{record_name} (#{@dns_record_type}) not found in Cloudflare"
    end
  end

  def get_current_dns_record
    result = make_api_request('GET', "/zones/#{@zone_id}/dns_records/#{@dns_record_id}")
    result['result'] ? result['result']['content'] : nil
  rescue => e
    puts "Error getting current DNS record: #{e.message}"
    nil
  end

  def update_dns_record(new_ip)
    # Get existing record to preserve settings
    existing_record = make_api_request('GET', "/zones/#{@zone_id}/dns_records/#{@dns_record_id}")
    record = existing_record['result']
    
    record_name = @dns_record_name == '@' ? @domain : "#{@dns_record_name}.#{@domain}"
    
    update_data = {
      'type' => @dns_record_type,
      'name' => record_name,
      'content' => new_ip,
      'ttl' => record['ttl'] || 3600,
      'proxied' => record['proxied'] || false
    }

    result = make_api_request('PUT', "/zones/#{@zone_id}/dns_records/#{@dns_record_id}", update_data)
    
    if result['success']
      puts "Successfully updated DNS record #{record_name} to #{new_ip}"
      true
    else
      raise "Failed to update DNS record: #{result['errors']}"
    end
  end

  def check_and_update
    current_ip = get_external_ip
    last_ip = get_last_known_ip

    if last_ip.nil?
      puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] No previous IP found. Saving current IP: #{current_ip}"
      save_ip(current_ip)
    elsif current_ip != last_ip
      puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] IP changed from #{last_ip} to #{current_ip}"
      puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] Updating Cloudflare DNS..."
      update_dns_record(current_ip)
      save_ip(current_ip)
      puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] Update complete!"
    else
      puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] IP unchanged (#{current_ip}) - no update needed"
    end
  end
end

# Main execution
if __FILE__ == $0
  begin
    updater = CloudflareIPUpdater.new
    
    if ARGV.include?('--help') || ARGV.include?('-h')
      puts <<~HELP
        Cloudflare IP Updater
        
        This script checks your external IP address and updates your Cloudflare DNS
        records automatically when it changes. It is designed to run via systemd timer.
        
        Configuration:
          Configuration is read from /etc/cloudflare-ip-updater/config
          
          Required settings:
            CLOUDFLARE_API_TOKEN       - Your Cloudflare API token
            DOMAIN                     - Your domain name (e.g., example.com)
          
          Optional settings (will be auto-detected if not provided):
            CLOUDFLARE_ZONE_ID         - Your Cloudflare Zone ID (auto-detected from domain)
            CLOUDFLARE_DNS_RECORD_ID   - Your DNS Record ID (auto-detected from name/type)
            DNS_RECORD_NAME            - DNS record name (@ for root, or subdomain) (default: @)
            DNS_RECORD_TYPE            - DNS record type (default: A)
        
        Usage:
          # Run once (typically called by systemd timer)
          /usr/sbin/cloudflare-ip-updater
          
          # View help
          /usr/sbin/cloudflare-ip-updater --help
          
        Service Management:
          # Enable and start the timer
          sudo systemctl enable cloudflare-ip-updater.service
          sudo systemctl enable --now cloudflare-ip-updater.timer
          
          # Check timer status
          sudo systemctl status cloudflare-ip-updater.timer
          
          # Check service logs
          sudo journalctl -u cloudflare-ip-updater.service
          
          # Manually trigger a check
          sudo systemctl start cloudflare-ip-updater.service
      
        To get Cloudflare API token:
          1. Go to https://dash.cloudflare.com/profile/api-tokens
          2. Click "Create Token"
          3. Use "Edit zone DNS" template or create custom token with Zone:Zone:Read and Zone:DNS:Edit permissions
          4. Add token to /etc/cloudflare-ip-updater/config
      HELP
      exit 0
    else
      updater.check_and_update
    end
  rescue => e
    puts "Error: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    exit 1
  end
end

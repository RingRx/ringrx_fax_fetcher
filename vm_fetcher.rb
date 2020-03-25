#!/usr/bin/ruby
# frozen_string_literal: true

require 'httparty'
require 'httmultiparty'
require 'json'
require 'yaml'
require 'logger'
require 'pp'
require 'fileutils'

@conffile = YAML.load_file('./vm_fetcher.conf')

puts @conffile

dest_dir = @conffile['destination_dir']
Dir.mkdir(dest_dir) unless Dir.exist?(dest_dir)

log_dir = "logs/"
Dir.mkdir(log_dir) unless Dir.exist?(log_dir)

tmp_dir = @conffile['tempdir']
Dir.mkdir(tmp_dir) unless Dir.exist?(tmp_dir)


logfile = "logs/#{@conffile['logfile']}"
logfilerotation = (@conffile['logfilerotation']).to_s

$LOG = Logger.new(logfile, logfilerotation)
$LOG.level = Logger::WARN


####################################################################
### Defining functions
####################################################################


  def auth
    body = {}
    body[:username] = @conffile['acct_username']
    body[:password] = @conffile['acct_password']

    response = HTTParty.post("#{@conffile['portal_url']}/auth/token",
      :body => body.to_json,
      :timeout => 10,
      :headers => { 'Content-Type' => 'application/json' } )
    return response
  end


  def fetch_messages
    url = "#{@conffile['portal_url']}/voicemails"
    headers = {}
    headers[:'Content-Type'] = "application/json"
    headers[:'Authorization: Bearer'] = @auth_token

    puts headers

    response = HTTParty.get(url,
      :timeout => 10,
      :headers => headers )
    return response
  end

  def fetch_fax_payload(msgid)
    url = "#{@conffile['portal_url']}/voicemails/#{msgid}/fax_payload"
    headers = {}
    headers[:'Content-Type'] = "application/json"
    headers[:'Authorization: Bearer'] = @auth_token

    puts headers

    response = HTTParty.get(url,
      :timeout => 10,
      :headers => headers )
    return response
  end

  def fetch_voice_payload(msgid)
    url = "#{@conffile['portal_url']}/voicemails/#{msgid}/voice_payload"
    headers = {}
    headers[:'Content-Type'] = "application/json"
    headers[:'Authorization: Bearer'] = @auth_token

    puts headers

    response = HTTParty.get(url,
      :timeout => 10,
      :headers => headers )
    return response
  end

  def faxfile_name(msg)
    file_ext = msg["fax"].split(".").last
    file_str = "#{@conffile['destination_filename']}.#{file_ext}"
    puts file_str
    output = file_str.gsub("{id}", msg["id"]).gsub("{caller}", msg["caller"]).gsub("{called}", msg["called"]).gsub("{created}", msg["created_at"]).gsub(" ", "_").gsub("{mailbox}", msg["mailbox"]).gsub("{type}", msg["message_type"])
    return output
  end



####################################################################
### Main app logic
####################################################################

puts "Starting up"

auth_resp = auth

puts auth_resp.code
puts auth_resp['access_token']

if auth_resp.code == 200
  puts "auth succeeded..setting auth token to #{auth_resp['access_token']}"
  @auth_token = auth_resp['access_token']
end

if @auth_token
  $LOG.warn "Performing mailbox fetch operation"
  puts "received auth token. Good to proceed"
  puts "Fetching voicemail mailbox"

  mbx = fetch_messages.parsed_response
  $LOG.warn "Mailbox retrieved, processing #{mbx.count} messages"
  mbx.each do |msg| 
    if msg["message_type"] == "fax"
      puts "Reviewing #{msg["id"]}"
      $LOG.warn "Downloading #{msg["id"]} created_at:#{msg["created_at"]} from:#{msg['caller']} to:#{msg["called"]} pages:#{msg["pages"]}"
      faxfile = fetch_fax_payload(msg["id"])
      puts "Reviewing #{msg}"
      filename = faxfile_name(msg)
      puts "saving to #{@conffile['destination_dir']}/#{filename}"
      file = File.open("#{@conffile['destination_dir']}/#{filename}", 'wb')
      file.write faxfile.body
      file.close
    end
  end
  
  
else
  $LOG.warn "Authentication failed unable to fetch messages"
  puts "no auth token..stopping"
end


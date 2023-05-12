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

dest_dir = @conffile['destination_dir'].to_s
Dir.mkdir(dest_dir) unless Dir.exist?(dest_dir)

log_dir = "logs/"
Dir.mkdir(log_dir) unless Dir.exist?(log_dir)

tmp_dir = @conffile['tempdir'].to_s
Dir.mkdir(tmp_dir) unless Dir.exist?(tmp_dir)

db_dir = 'db/'
Dir.mkdir(db_dir) unless Dir.exist?(db_dir)

db_file = File.join('db', 'messageids')
File.open(db_file, 'a') { |f| f.close } unless File.exist?(db_file)

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
      :headers => { 'Content-Type' => 'application/json' },
      :verify => false )
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
      :headers => headers,
      :verify => false )
    return response
  end

  def fetch_payload(msgtype, msgid)
    if (msgtype == "fax")
      url = "#{@conffile['portal_url']}/voicemails/#{msgid}/fax_payload"
    elsif (msgtype == "voicemail")
      url = "#{@conffile['portal_url']}/voicemails/#{msgid}/voice_payload"
    end
    headers = {}
    headers[:'Content-Type'] = "application/json"
    headers[:'Authorization: Bearer'] = @auth_token

    puts headers

    response = HTTParty.get(url,
      :timeout => 10,
      :headers => headers,
      :verify => false )
    return response
  end

  def file_name(msg)
    if msg["message_type"] == "message"
      file_ext = "txt"
    elsif msg["message_type"] == "fax"
      file_ext = msg["fax"].split(".").last
    elsif msg["message_type"] == "voicemail"
      file_ext = msg["voicemail"].split(".").last
    end
    file_str = "#{@conffile['destination_filename']}.#{file_ext}"
    output = file_str.gsub("{id}", msg["id"]).gsub("{caller}", msg["caller"]).gsub("{called}", msg["called"]).gsub("{created}", msg["created_at"]).gsub(" ", "_").gsub("{mailbox}", msg["mailbox"]).gsub("{type}", msg["message_type"]).gsub(':', '.')
    return output
  end

  def message_ids
    db_file = File.join('db','messageids')
    file = File.open(db_file, 'r')
    msgids = file.readlines.map(&:chomp)
    file.close
    return msgids
  end

  def message_id_check(msg)
    if @conffile['message_redownload']
      result = true
    else
      db_file = File.join('db','messageids')
      result = true
      if File.exists?(db_file)
        $LOG.debug "Checking id #{msg['id']}"
        if message_ids.include?(msg['id'])
          result = false
        else
          File.open(db_file, 'a') { |f| f.write("#{msg['id']}\n") }
        end
      else
        File.open(db_file, 'a') { |f| f.write("#{msg['id']}\n") }
      end
    end
    return result
  end

  def message_type_check(type)
    @types || @types = @conffile['message_types']
    @types.include?(type)
  end

  def delete_messge(msgid)
    url = "#{@conffile['portal_url']}/voicemails/#{msgid}"

    headers = {}
    headers[:'Content-Type'] = "application/json"
    headers[:'Authorization: Bearer'] = @auth_token

    response = HTTParty.delete(url,
      :timeout => 10,
      :headers => headers,
      :verify => false )
    return response
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
    begin 
      puts "Reviewing #{msg["id"]}"
      if !message_id_check(msg) || !message_type_check(msg["message_type"])
        $LOG.warn "Skipping messsage #{msg["id"]} type: #{msg["message_type"]}"
        next
      end
      $LOG.warn "Downloading #{msg["id"]} message_type: #{msg["message_type"]} created_at:#{msg["created_at"]} from:#{msg['caller']} to:#{msg["called"]} pages:#{msg["pages"]}"
      payloadfile = fetch_payload(msg["message_type"], msg["id"]) if msg["message_type"] == "fax" or msg["message_type"] == "voicemail"
      puts "Reviewing #{msg}"
      filename = file_name(msg)
      puts "saving to #{@conffile['destination_dir']}/#{filename}"
      file = File.open(File.join(@conffile['destination_dir'].to_s, filename), 'wb')
      file.write payloadfile.body if msg["message_type"] == "fax" or msg["message_type"] == "voicemail"
      file.write msg["message"] if msg["message_type"] == "message"
      file.close
      if @conffile['delete_messages_after_fetch'] == true
        $LOG.warn "Deleting message #{msg["id"]}" 
        delete_messge(msg["id"])
      end
    rescue => e
      $LOG.warn "Failed to download message #{msg["id"]} error: #{e} "
    end
  end

else
  $LOG.warn "Authentication failed unable to fetch messages"
  puts "no auth token..stopping"
end


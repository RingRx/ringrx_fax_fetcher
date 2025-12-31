#!/usr/bin/ruby
# frozen_string_literal: true

require 'httparty'
require 'json'
require 'yaml'
require 'logger'
require 'pp'
require 'fileutils'
require 'optparse'

# Parse command-line arguments
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on("-c", "--config FILE", "Path to configuration file (default: ./vm_fetcher.conf)") do |file|
    options[:config] = file
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

config_file = options[:config] || './vm_fetcher.conf'

unless File.exist?(config_file)
  puts "Error: Configuration file not found: #{config_file}"
  exit 1
end

@conffile = YAML.load_file(config_file)

puts @conffile

# Set up destination directory
dest_dir = @conffile['destination_dir'].to_s
Dir.mkdir(dest_dir) unless Dir.exist?(dest_dir)

# Create per-folder destination directories if configured
if @conffile['folder_dirs']
  @conffile['folder_dirs'].each do |_folder, dir|
    Dir.mkdir(dir.to_s) unless Dir.exist?(dir.to_s)
  end
end

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
    if @conffile['api_token']
      body = { token: @conffile['api_token'], secret:  @conffile['api_secret'] }
    else
      body = { username: @conffile['acct_username'], password:  @conffile['acct_password'] }
    end

    response = HTTParty.post("#{@conffile['portal_url']}/auth/token",
      :body => body.to_json,
      :timeout => 10,
      :headers => { 'Content-Type' => 'application/json' },
      :verify => false )
    return response
  end


  def fetch_messages(folder = 'inbox')
    url = "#{@conffile['portal_url']}/voicemails"
    url += "?message_folder=#{folder}" if folder
    headers = {}
    headers[:'Content-Type'] = "application/json"
    headers[:'Authorization: Bearer'] = @auth_token

    puts headers

    response = HTTParty.get(url,
      :timeout => 60,
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

  def file_name(msg, folder = 'inbox')
    if msg["message_type"] == "message"
      file_ext = "txt"
    elsif msg["message_type"] == "fax"
      file_ext = msg["fax"].split(".").last
    elsif msg["message_type"] == "oncall"
      file_ext = msg["voicemail"].split(".").last
    elsif msg["message_type"] == "voicemail"
      file_ext = msg["voicemail"].split(".").last
    end
    file_str = "#{@conffile['destination_filename']}.#{file_ext}"
    output = file_str.gsub("{id}", msg["id"]).gsub("{caller}", msg["caller"]).gsub("{called}", msg["called"]).gsub("{created}", msg["created_at"]).gsub(" ", "_").gsub("{mailbox}", msg["mailbox"]).gsub("{type}", msg["message_type"]).gsub("{folder}", folder).gsub(':', '.')
    return output
  end

  def transcription_file_name(msg, folder = 'inbox')
    file_str = "#{@conffile['destination_filename']}.txt"
    output = file_str.gsub("{id}", msg["id"]).gsub("{caller}", msg["caller"]).gsub("{called}", msg["called"]).gsub("{created}", msg["created_at"]).gsub(" ", "_").gsub("{mailbox}", msg["mailbox"]).gsub("{type}", msg["message_type"]).gsub("{folder}", folder).gsub(':', '.')
    return output
  end

  def has_transcription?(msg)
    result = false
    if msg['transcription'].length > 1
      result = true
    end
    result
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

  def destination_dir_for(folder = nil)
    # Check if per-folder destination directories are configured
    if folder && @conffile['folder_dirs'] && @conffile['folder_dirs'][folder]
      return @conffile['folder_dirs'][folder].to_s
    end
    # Fall back to the default destination_dir
    @conffile['destination_dir'].to_s
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
  
  # Get folders to fetch from config, default to ['inbox'] for backwards compatibility
  folders = @conffile['message_folders'] || ['inbox']
  folders = [folders] if folders.is_a?(String)  # Handle single folder as string
  
  folders.each do |folder|
    puts "Fetching messages from folder: #{folder}"
    $LOG.warn "Fetching messages from folder: #{folder}"

    mbx = fetch_messages(folder).parsed_response
    
    if mbx.nil? || !mbx.is_a?(Array)
      $LOG.warn "No messages or invalid response for folder: #{folder}"
      puts "No messages found in folder: #{folder}"
      next
    end
    
    $LOG.warn "Folder #{folder}: retrieved #{mbx.count} messages"

    mbx.each do |msg| 
      begin 
        puts "Reviewing #{msg["id"]}"
        if !message_id_check(msg) || !message_type_check(msg["message_type"])
          $LOG.warn "Skipping messsage #{msg["id"]} type: #{msg["message_type"]}"
          next
        end
        $LOG.warn "Downloading #{msg["id"]} folder: #{folder} message_type: #{msg["message_type"]} created_at:#{msg["created_at"]} from:#{msg['caller']} to:#{msg["called"]} pages:#{msg["pages"]}"
        payloadfile = fetch_payload(msg["message_type"], msg["id"]) if msg["message_type"] == "fax" or msg["message_type"] == "voicemail"
        puts "Reviewing #{msg}"
        filename = file_name(msg, folder)
        msg_dest_dir = destination_dir_for(folder)
        puts "saving to #{msg_dest_dir}/#{filename}"
        file = File.open(File.join(msg_dest_dir, filename), 'wb')
        file.write payloadfile.body if msg["message_type"] == "fax" or msg["message_type"] == "voicemail" or msg["message_type"] == "oncall"
        file.write msg["message"] if msg["message_type"] == "message"
        file.close
        if @conffile['message_transcription_to_file'] == true && has_transcription?(msg)
          text_filename = transcription_file_name(msg, folder)
          text_file = File.open(File.join(msg_dest_dir, text_filename), 'wb')
          text_file.write msg["transcription"] if msg["message_type"] == "oncall" or msg["message_type"] == "voicemail"
          text_file.close
        end
        if @conffile['delete_messages_after_fetch'] == true
          $LOG.warn "Deleting message #{msg["id"]}" 
          delete_messge(msg["id"])
        end
      rescue => e
        $LOG.warn "Failed to download message #{msg["id"]} error: #{e} "
      end
    end
  end

else
  $LOG.warn "Authentication failed unable to fetch messages"
  puts "no auth token..stopping"
end


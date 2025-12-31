### Installation

    gem install ocra
    bundle install

For more details about ocra https://github.com/larsch/ocra

### Usage

    ruby vm_fetcher.rb [options]

**Options:**
- `-c`, `--config FILE` - Path to configuration file (default: `./vm_fetcher.conf`)
- `-h`, `--help` - Show help message

**Examples:**

    # Use default config file (./vm_fetcher.conf)
    ruby vm_fetcher.rb

    # Use a custom config file
    ruby vm_fetcher.rb --config /path/to/my_config.conf
    ruby vm_fetcher.rb -c production.conf

### Configuration

Copy `vm_fetcher.conf.example` to `vm_fetcher.conf` and customize the settings.

**API folders:** You can specify which API folders to fetch messages from:

```yaml
# Fetch from inbox only (default)
message_folders: [inbox]

# Fetch from multiple folders
message_folders: [inbox, sent, outbox]
```

Valid folders: `inbox`, `sent`, `trash`, `outbox`

**Per-folder destination directories:** You can save messages from different API folders to different local directories:

```yaml
folder_dirs:
  inbox: received
  sent: sent_items
  outbox: pending
```

**Filename tokens:** Use `{folder}` in `destination_filename` to include the folder name:

```yaml
destination_filename: "{folder}_{type}_{id}_{caller}_{called}_{created}"
```

### Building an executable:

    ocra .\vm_fetcher.rb --console --no-autoload --gem-ful --add-all-core --dll ruby_builtin_dlls/libgmp-10.dll --dll ruby_builtin_dlls/libffi-7.dll --dll ruby_builtin_dlls/zlib1.dll --dll ruby_builtin_dlls/libiconv-2.dll --dll ruby_builtin_dlls\libssp-0.dll --dll ruby_builtin_dlls\libssl-1_1-x64.dll --dll ruby_builtin_dlls\libcrypto-1_1-x64.dll --dll ruby_builtin_dlls\libyaml-0-2.dll --dll ruby_builtin_dlls/libwinpthread-1.dll --dll ruby_builtin_dlls\libgcc_s_seh-1.dll



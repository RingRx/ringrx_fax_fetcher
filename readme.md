### Installation

    gem install ocra
    bundle install

For more details about ocra https://github.com/larsch/ocra

### Building an executable:

    ocra .\vm_fetcher.rb --console --no-autoload --gem-ful --add-all-core --dll ruby_builtin_dlls/libgmp-10.dll --dll ruby_builtin_dlls/libffi-7.dll --dll ruby_builtin_dlls/zlib1.dll --dll ruby_builtin_dlls/libiconv-2.dll --dll ruby_builtin_dlls\libssp-0.dll --dll ruby_builtin_dlls\libssl-1_1-x64.dll --dll ruby_builtin_dlls\libcrypto-1_1-x64.dll --dll ruby_builtin_dlls\libyaml-0-2.dll --dll ruby_builtin_dlls/libwinpthread-1.dll --dll ruby_builtin_dlls\libgcc_s_seh-1.dll



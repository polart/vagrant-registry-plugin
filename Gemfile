source "https://rubygems.org"

group :development do
  gem "rake"
  gem "vagrant", git: "https://github.com/hashicorp/vagrant.git"
  gem "vagrant-spec", git: "https://github.com/hashicorp/vagrant-spec.git"
end

group :plugins do
  gem 'vagrant-registry', path: '.'
end

group :test do
  gem "webmock", require: false
  gem 'simplecov', require: false
end

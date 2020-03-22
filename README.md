# Vagrant Registry plugin

Vagrant Registry plugin allows you to use Vagrant to access private boxes from self-hosted [Vagrant Registry](https://github.com/polart/vagrant-registry).

<p align="center"><img src="img/vr.gif?raw=true"/></p>

## Usage

The plugin adds two commands: 

- `login` - login into self-hosted Vagrant Registry
    ```
    $ vagrant registry login http://localhost:3000
    ```

- `push` - push box file into self-hosted Vagrant Registry
    ```
    $ vagrant registry push test.box http://localhost:3000/polart/test 0.1.0 virtualbox
    ```

## Installation

Build package
```
$ bundle exec rake build
```

Install plugin into Vagrant
```
$ vagrant plugin install pkg/vagrant-registry-0.1.0.gem
```


## Development

Install dependencies
```
$ bundle install
```

Run tests
```
$ bundle exec rake test
```

Run the plugin within Vagrant dev build
```
$ bundle exec vagrant registry
```

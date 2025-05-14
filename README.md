# Logstash Salesforce input Plugin

This Logstash input plugin allows you to query Salesforce using SOQL and puts the results
into Logstash, one row per event. You can configure it to pull entire sObjects or only
specific fields.

This is a plugin for [Logstash](https://github.com/elasticsearch/logstash).

It is fully free and fully open source. The license is Apache 2.0, meaning you are pretty much free to use it however you want in whatever way.

## How to use

Add the input plugin to your Logstash pipeline definition.

This example queries all the Salesforce Opportunities and publishes an event for each opportunity found:

```ruby
input {
  salesforce {
    client_id => 'OAUTH CLIENT ID FROM YOUR SFDC APP'
    client_secret => 'OAUTH CLIENT SECRET FROM YOUR SFDC APP'
    username => 'email@example.com'
    password => 'super-secret'
    security_token => 'SECURITY TOKEN FOR THIS USER'
    sfdc_object_name => 'Opportunity'
  }
}
```

For more examples and an explanation of all configuration options, see https://www.elastic.co/docs/reference/logstash/plugins/plugins-inputs-salesforce.

## Documentation

Logstash provides infrastructure to automatically generate documentation for this plugin. We use the asciidoc format to write documentation so any comments in the source code will be first converted into asciidoc and then into html. All plugin documentation are placed under one [central location](http://www.elasticsearch.org/guide/en/logstash/current/).

- For formatting code or config example, you can use the asciidoc `[source,ruby]` directive
- For more asciidoc formatting tips, see the excellent reference here https://github.com/elasticsearch/docs#asciidoc-guide

## Need Help?

Need help? Try #logstash on freenode IRC or the https://discuss.elastic.co/c/logstash discussion forum.

## Developing

### 1. Plugin Development and Testing

#### Code

- To get started, you'll need JRuby with the Bundler gem installed. We strongly recommend
  using a Ruby Version Manager such as `rvm` to install JRuby. If you're using a JRuby installed
  by Homebrew on macOS, replace the `bundle` command with `jbundle` in all examples in this
  document: Homebrew renames the JRuby binaries so that they don't clash with those from the system
  (C) Ruby that ships with macOS.

- Clone the plugin code from the GitHub [logstash-plugins/logstash-input-salesforce](https://github.com/logstash-plugins/logstash-input-salesforce) repository.

- Install dependencies
```sh
bundle install --path=vendor/bundle
```

- Download a source release of the Logstash version you're targeting 
  (e.g. https://github.com/elastic/logstash/archive/refs/tags/v8.14.3.zip) and
  extract (unzip) it to a local directory.

#### Test

- Update your dependencies

```sh
bundle install --path=vendor/bundle
```

- Run tests

```sh
export LOGSTASH_PATH=<path to logstash source>
export LOGSTASH_SOURCE=1
bundle exec rspec
```

If you get an error like `Could not find logstash-core-plugin-api-2.1.16-java, logstash-core-8.14.3-java in locally 
installed gems`, double check that you've set and exported the `LOGSTASH_PATH` and `LOGSTASH_SOURCE` environment
variables as explained in the previous section, and that the `LOGSTASH_PATH` points to an unzipped Logstash source 
distribution.

### 2. Running your unpublished Plugin in Logstash

#### 2.1 Run in a local Logstash clone

- Edit Logstash `Gemfile` and add the local plugin path, for example:
```ruby
gem "logstash-input-salesforce", :path => "/your/local/logstash-input-salesforce"
```
- Install plugin
```sh
# Logstash 2.3 and higher
bin/logstash-plugin install --no-verify

# Prior to Logstash 2.3
bin/plugin install --no-verify

```
- Run Logstash with your plugin
```sh
bin/logstash -e 'input { salesforce { ... } }'
```
At this point any modifications to the plugin code will be applied to this local Logstash setup. After modifying the plugin, simply rerun Logstash.

#### 2.2 Run in an installed Logstash

You can use the same **2.1** method to run your plugin in an installed Logstash by editing its `Gemfile` and pointing the `:path` to your local plugin development directory or you can build the gem and install it using:

- Build your plugin gem
```sh
gem build logstash-input-salesforce.gemspec
```
- Install the plugin from the Logstash home
```sh
# Logstash 2.3 and higher
bin/logstash-plugin install --no-verify

# Prior to Logstash 2.3
bin/plugin install --no-verify

```
- Start Logstash and proceed to test the plugin

## Contributing

All contributions are welcome: ideas, patches, documentation, bug reports, complaints, and even something you drew up on a napkin.

Programming is not a required skill. Whatever you've seen about open source and maintainers or community members  saying "send patches or die" - you will not see that here.

It is more important to the community that you are able to contribute.

For more information about contributing, see the [CONTRIBUTING](https://github.com/elasticsearch/logstash/blob/master/CONTRIBUTING.md) file.

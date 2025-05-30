## 3.3.0
  - Added `timeout` configuration to override the connect/read timeout for REST requests to Salesforce
  - Added `interval` configuration to run the plugin continuously, querying records and publishing events 
    for them at a set interval instead of running once and quitting
  - Added incremental data loading feature, controlled by configuration options `tracking_field`, `tracking_field_value_file`, and `changed_data_filter`

## 3.2.1
  - Changes sensitive configs type to Password for better protection from leaks in debug logs. [#35](https://github.com/logstash-plugins/logstash-input-salesforce/pull/35)

## 3.2.0
  - Added `use_tooling_api` configuration to connect to the Salesforce Tooling API instead of the regular Rest API. [#26](https://github.com/logstash-plugins/logstash-input-salesforce/pull/26)

## 3.1.0
  - Added `sfdc_instance_url` configuration to connect to a specific url. [#28](https://github.com/logstash-plugins/logstash-input-salesforce/pull/28)
  - Switch to restforce v5+ (for logstash 8.x compatibility)

## 3.0.7
  - Added description for `SALESFORCE_PROXY_URI` environment variable.

## 3.0.6
  - Make sure 'recent' restforce dependency is used (to help dependency resolution)

## 3.0.5
  - Docs: Set the default_codec doc attribute.

## 3.0.4
  - Update gemspec summary

## 3.0.3
  - Fix some documentation issues

# 3.0.1
  - Correctly format time from salesforce events

# 3.0.0
  - Update dependency of logstash-core-plugin-api to ">= 1.60", "<= 2.99" (for logstash 5.x compatibility)
  - Update event api to .set and .get accessors

# 2.0.4
  - Depend on logstash-core-plugin-api instead of logstash-core, removing the need to mass update plugins on major releases of logstash

# 2.0.3
  - New dependency requirements for logstash-core for the 5.0 release

## 2.0.0
 - Plugins were updated to follow the new shutdown semantic, this mainly allows Logstash to instruct input plugins to terminate gracefully,
   instead of using Thread.raise on the plugins' threads. Ref: https://github.com/elastic/logstash/pull/3895
 - Dependency on logstash-core update to 2.0

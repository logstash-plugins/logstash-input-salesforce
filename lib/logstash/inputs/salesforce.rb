# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "time"

# This Logstash input plugin allows you to query Salesforce using SOQL and puts the results
# into Logstash, one row per event. You can configure it to pull entire sObjects or only
# specific fields.
#
# NOTE: This input plugin will stop after all the results of the query are processed and will
# need to be re-run to fetch new results. It does not utilize the streaming API.
#
# In order to use this plugin, you will need to create a new SFDC Application using
# oauth. More details can be found here:
# https://help.salesforce.com/apex/HTViewHelpDoc?id=connected_app_create.htm
#
# You will also need a username, password, and security token for your salesforce instance.
# More details for generating a token can be found here:
# https://help.salesforce.com/apex/HTViewHelpDoc?id=user_security_token.htm
#
# In addition to specifying an sObject, you can also supply a list of API fields
# that will be used in the SOQL query.
#
# ==== Example
# This example prints all the Salesforce Opportunities to standard out
#
# [source,ruby]
# ----------------------------------
# input {
#   salesforce {
#     client_id => 'OAUTH CLIENT ID FROM YOUR SFDC APP'
#     client_secret => 'OAUTH CLIENT SECRET FROM YOUR SFDC APP'
#     username => 'email@example.com'
#     password => 'super-secret'
#     security_token => 'SECURITY TOKEN FOR THIS USER'
#     sfdc_soql_query => 'SELECT Id FROM Account'
#   }
# }
#
# output {
#   stdout {
#     codec => rubydebug
#   }
# }
# ----------------------------------

class LogStash::Inputs::Salesforce < LogStash::Inputs::Base

  config_name "salesforce"
  default :codec, "plain" #not used

  # Set this to true to connect via the Tooling API instead of the Rest API.
  # This allows accessing information like Apex Unit Test Results,
  # Flow Coverage Results, Security Health Check Risks, etc.
  # See https://developer.salesforce.com/docs/atlas.en-us.api_tooling.meta/api_tooling
  # for more details about the Tooling API
  config :use_tooling_api, :validate => :boolean, :default => false
  # Set this to true to connect to a sandbox sfdc instance
  # logging in through test.salesforce.com
  config :use_test_sandbox, :validate => :boolean, :default => false
  # Include deleted records
  config :include_deleted, :validate => :boolean, :default => false
  # Set this to the instance url of the sfdc instance you want
  # to connect to already during login. If you have configured
  # a MyDomain in your sfdc instance you would provide
  # <mydomain>.my.salesforce.com here.
  config :sfdc_instance_url, :validate => :string, :required => false
  # By default, this uses the default Restforce API version.
  # To override this, set this to something like "32.0" for example
  config :api_version, :validate => :string, :required => false
  # RESTForce request timeout in seconds.
  config :timeout, :validate => :number, :required => false
  # Consumer Key for authentication. You must set up a new SFDC
  # connected app with oath to use this output. More information
  # can be found here:
  # https://help.salesforce.com/apex/HTViewHelpDoc?id=connected_app_create.htm
  config :client_id, :validate => :string, :required => true
  # Consumer Secret from your oauth enabled connected app
  config :client_secret, :validate => :string, :required => true
  # A valid salesforce user name, usually your email address.
  # Used for authentication and will be the user all objects
  # are created or modified by
  config :username, :validate => :string, :required => true
  # The password used to login to sfdc
  config :password, :validate => :string, :required => true
  # The security token for this account. For more information about
  # generting a security token, see:
  # https://help.salesforce.com/apex/HTViewHelpDoc?id=user_security_token.htm
  config :security_token, :validate => :string, :required => true
  # Plain SOQL query
  config :sfdc_soql_query, :validate => :string, :required => true
  # Setting this to true will convert SFDC's NamedFields__c to named_fields__c
  config :to_underscores, :validate => :boolean, :default => false

  public
  def register
    require 'restforce'
    @sfdc_fields = get_sfdc_fields
  end # def register

  public
  def run(queue)
    if @include_deleted
      results = client.query_all(@sfdc_soql_query)
    else
      results = client.query(@sfdc_soql_query)
    end

    @logger.debug("Query results:", :results => results)
    if results && results.first
      results.each do |result|
        event = LogStash::Event.new()
        decorate(event)
        @sfdc_fields.each do |field|
          # PARENT.CHILD => PARENT
          # function(field) field => field
          field = field.split(/\./).first.split(/\s/).last
          value = result.send(field)

          # Remove RESTForce's nested 'attributes' field for reference fields
          value.is_a?(Hash) ? value = value.tap { |hash| hash.delete(:attributes)} : value

          event_key = @to_underscores ? underscore(field) : field
          event.set(event_key, value)
        end
        queue << event
      end
    end
  end # def run

  private
  def client
    if @use_tooling_api
      @client ||= Restforce.tooling client_options
    else
      @client ||= Restforce.new client_options
    end
  end

  private
  def client_options
    options = {
      :username       => @username,
      :password       => @password,
      :security_token => @security_token,
      :client_id      => @client_id,
      :client_secret  => @client_secret
    }
    # configure the endpoint to which restforce connects to for authentication
    if @sfdc_instance_url && @use_test_sandbox
      raise ::LogStash::ConfigurationError.new("Both \"use_test_sandbox\" and \"sfdc_instance_url\" can't be set simultaneously. Please specify either \"use_test_sandbox\" or \"sfdc_instance_url\"")
    elsif @sfdc_instance_url
      options.merge!({ :host => @sfdc_instance_url })
    elsif @use_test_sandbox
      options.merge!({ :host => "test.salesforce.com" })
    end
    options.merge!({ :api_version => @api_version }) if @api_version
    options.merge!({ :timeout => @timeout }) if @timeout
    return options
  end

  private
  def get_sfdc_fields
    extracted_fields = sfdc_soql_query.gsub(/SELECT (.+) FROM.+/i, '\1')
    extracted_fields_as_array = extracted_fields.split(',').collect { |item| item.strip }
    @logger.debug("Extracted fields: ", :extracted_fields_as_array => extracted_fields_as_array.to_s)
    
    return extracted_fields_as_array;
  end

  private
  # From http://stackoverflow.com/a/1509957/4701287
  def underscore(camel_cased_word)
    camel_cased_word.to_s.gsub(/::/, '/').
       gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
       gsub(/([a-z\d])([A-Z])/,'\1_\2').
       tr("-", "_").
       downcase
  end

  private
  def format_time(string)
    # salesforce can use different time formats so until we have a higher
    # performance requirement we can just use Time.parse
    # otherwise it's possible to use a sequence of DateTime.strptime, for example
    LogStash::Timestamp.new(Time.parse(string))
  end

end # class LogStash::Inputs::Salesforce

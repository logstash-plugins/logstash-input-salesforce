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
#     sfdc_object_name => 'Opportunity'
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

  # Set this to true to connect to a sandbox sfdc instance
  # logging in through test.salesforce.com
  config :use_test_sandbox, :validate => :boolean, :default => false
  # By default, this uses the default Restforce API version.
  # To override this, set this to something like "32.0" for example
  config :api_version, :validate => :string, :required => false
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
  # The name of the salesforce object you are creating or updating
  config :sfdc_object_name, :validate => :string, :required => true
  # These are the field names to return in the Salesforce query
  # If this is empty, all fields are returned.
  config :sfdc_fields, :validate => :array, :default => []
  # These options will be added to the WHERE clause in the
  # SOQL statement. Additional fields can be filtered on by
  # adding field1 = value1 AND field2 = value2 AND...
  config :sfdc_filters, :validate => :string, :default => ""
  # Setting this to true will convert SFDC's NamedFields__c to named_fields__c
  config :to_underscores, :validate => :boolean, :default => false

  public
  def register
    require 'restforce'
    obj_desc = client.describe(@sfdc_object_name)
    @sfdc_field_types = get_field_types(obj_desc)
    @sfdc_fields = get_all_fields if @sfdc_fields.empty?
  end # def register

  public
  def run(queue)
    results = client.query(get_query())
    if results && results.first
      results.each do |result|
        event = LogStash::Event.new()
        decorate(event)
        @sfdc_fields.each do |field|
          field_type = @sfdc_field_types[field]
          field_symbol = field.split('.').map(&:to_sym)
          value = result.dig(*field_symbol)
          event_key = @to_underscores ? underscore(field) : field
          if not value.nil?
            case field_type
            when 'datetime', 'date'
              event.set(event_key, format_time(value))
            else
              event.set(event_key, value)
            end
          end
        end
        queue << event
      end
    end
  end # def run

  private
  def client
    @client ||= Restforce.new client_options
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
    options.merge!({ :host => "test.salesforce.com" }) if @use_test_sandbox
    options.merge!({ :api_version => @api_version }) if @api_version
    return options
  end

  private
  def get_query()
    query = ["SELECT",@sfdc_fields.join(','),
             "FROM",@sfdc_object_name]
    query << ["WHERE",@sfdc_filters] unless @sfdc_filters.empty?
    query << "ORDER BY LastModifiedDate DESC" if @sfdc_fields.include?('LastModifiedDate')
    query_str = query.flatten.join(" ")
    @logger.debug? && @logger.debug("SFDC Query", :query => query_str)
    return query_str
  end

  private
  def get_field_types(obj_desc)
    field_types = {}
    obj_desc.fields.each do |f|
      field_types[f.name] = f.type
    end
    @logger.debug? && @logger.debug("Field types", :field_types => field_types.to_s)
    return field_types
  end

  private
  def get_all_fields
    return @sfdc_field_types.keys
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

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
#     sfdc_object_names => ['Account','User']
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
  
  # A list of the salesforce objects you are pulling. If you are specifying
  # more than one, you should probably be very careful about using the sfdc_fields
  # and sfdc_filters configuration options.
  config :sfdc_object_names, :validate => :array, :required => true
    
  # These are the field names to return in the Salesforce query
  # If this is empty, all fields are returned.
  # NOTE: If specifying multiple objects to pull, these fields must
  # be valid for ALL objects being pulled. Using this with multiple
  # sObjects is probably not a good idea.
  config :sfdc_fields, :validate => :array, :default => []

  # These options will be added to the WHERE clause in the
  # SOQL statement. Additional fields can be filtered on by
  # adding field1 = value1 AND field2 = value2 AND...
  # NOTE: If specifying multiple objects to pull, these filters must
  # be valid for ALL objects being pulled.
  config :sfdc_filters, :validate => :string, :default => ""

  # Setting this to true will convert SFDC's NamedFields__c to named_fields__c
  config :to_underscores, :validate => :boolean, :default => false

  # This will add a field to the event letting you know what sObject the event is.
  # This is useful for filtering when specifying multiple objects names to query.
  config :sfdc_object_type_field, :validate => :string, :required => false
  
  # Interval to run the command. Value is in seconds. If no interval is given,
  # this plugin only fetches data once.
  config :interval, :validate => :number, :required => false, :default => -1
  
    
  public
  def register
    require 'restforce'
  end # def register

  public
  def run(queue)
    while !stop?
      start = Time.now
      @sfdc_object_names.each do |sfdc_object_name|
        obj_desc = client.describe(sfdc_object_name)
        @sfdc_field_types = get_field_types(obj_desc)
        current_sfdc_fields = (@sfdc_fields.empty?) ? get_all_fields : @sfdc_fields

        results = client.query(get_query(current_sfdc_fields,sfdc_object_name))
        if results && results.first
          results.each do |result|
            event = LogStash::Event.new()
            decorate(event)
            current_sfdc_fields.each do |field|
              field_type = @sfdc_field_types[field]
              value = result.send(field)
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
            event.set(@sfdc_object_type_field, sfdc_object_name) if @sfdc_object_type_field
            queue << event
          end
        end
      end # loop sObjects
      if @interval == -1
        break
      else
        duration = Time.now - start
        # Sleep for the remainder of the interval, or 0 if the duration ran
        # longer than the interval.
        sleeptime = [0, @interval - duration].max
        if sleeptime == 0
            @logger.warn("Execution ran longer than the interval. Skipping sleep.",
                       :duration => duration,
                       :interval => @interval)
        else
            sleep(sleeptime)
        end
      end  # end interval check    
      Stud.stoppable_sleep(@interval) { stop? }
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
  def get_query(sfdc_fields,sfdc_object_name)
    query = ["SELECT",sfdc_fields.join(','),
             "FROM",sfdc_object_name]
    query << ["WHERE",@sfdc_filters] unless @sfdc_filters.empty?
    query << "ORDER BY LastModifiedDate DESC" if sfdc_fields.include?('LastModifiedDate')
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

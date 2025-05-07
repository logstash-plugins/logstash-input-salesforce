# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "time"
require "stud/interval"

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

  # Set this to true to connect via the Tooling API instead of the Rest API.
  # This allows accessing information like Apex Unit Test Results,
  # Flow Coverage Results, Security Health Check Risks, etc.
  # See https://developer.salesforce.com/docs/atlas.en-us.api_tooling.meta/api_tooling
  # for more details about the Tooling API
  config :use_tooling_api, :validate => :boolean, :default => false

  # Set this to true to connect to a sandbox sfdc instance
  # logging in through test.salesforce.com
  config :use_test_sandbox, :validate => :boolean, :default => false

  # Set this to the instance url of the sfdc instance you want
  # to connect to already during login. If you have configured
  # a MyDomain in your sfdc instance you would provide
  # <mydomain>.my.salesforce.com here.
  config :sfdc_instance_url, :validate => :string, :required => false

  # By default, this uses the default Restforce API version.
  # To override this, set this to something like "32.0" for example
  config :api_version, :validate => :string, :required => false

  # Consumer Key for authentication. You must set up a new SFDC
  # connected app with oath to use this output. More information
  # can be found here:
  # https://help.salesforce.com/apex/HTViewHelpDoc?id=connected_app_create.htm
  config :client_id, :validate => :string, :required => true

  # Consumer Secret from your oauth enabled connected app
  config :client_secret, :validate => :password, :required => true

  # A valid salesforce user name, usually your email address.
  # Used for authentication and will be the user all objects
  # are created or modified by
  config :username, :validate => :string, :required => true

  # The password used to login to sfdc
  config :password, :validate => :password, :required => true

  # The security token for this account. For more information about
  # generting a security token, see:
  # https://help.salesforce.com/apex/HTViewHelpDoc?id=user_security_token.htm
  config :security_token, :validate => :password, :required => true

  # The name of the salesforce object you are creating or updating
  config :sfdc_object_name, :validate => :string, :required => true

  # These are the field names to return in the Salesforce query
  # If this is empty, all fields are returned.
  config :sfdc_fields, :validate => :array, :default => []

  # These options will be added to the WHERE clause in the
  # SOQL statement. Additional fields can be filtered on by
  # adding field1 = value1 AND field2 = value2 AND...
  config :sfdc_filters, :validate => :string, :default => ""

  # RESTForce request timeout in seconds.
  config :timeout, :validate => :number, :default => 60, :required => false

  # Setting this to true will convert SFDC's NamedFields__c to named_fields__c
  config :to_underscores, :validate => :boolean, :default => false

  # File that stores the tracking field's latest value. This is read before querying data to interpolate
  # the tracking field value into the incremental_filter, and the latest value of the tracking field is written
  # to it after all the query results have been read.
  config :tracking_field_value_file, :validate => :string, :required => false

  # Filter clause to use for incremental retrieval and indexing of data that has changed since the last invodation 
  # of the plugin. This is combined with sfdc_filters using the AND operator, if tracking_field_value_path exists. 
  # String interpolation is applied to replace "%{last_tracking_field_value}" in this string with the value read 
  # from tracking_field_value_file. This would usually be something like "tracking_field > '%{last_tracking_field_value}'" 
  # where tracking_field is the API name of the actual tracking field set using the tracking_field configuration property, 
  # e.g. LastModifiedDate
  config :changed_data_filter, :validate => :string, :required => false

  # The field from which the last value will be stored in the tracking_field_value_file and interpolated
  # for "%{last_tracking_field_value}" in the changed_data_filter expression. This field will also be used in an ORDER BY
  # clause added to the query, with sorting done ascending, so that the last value in the results is also the
  # highest.
  config :tracking_field, :validate => :string, :required => false

  # Interval to run the command. Value is in seconds. If no interval is given,
  # this plugin only fetches data once.
  config :interval, :validate => :number, :required => false, :default => -1

  public
  def register
    require 'restforce'
    obj_desc = client.describe(@sfdc_object_name)
    @sfdc_field_types = get_field_types(obj_desc)
    @sfdc_fields = get_all_fields if @sfdc_fields.empty?
  end # def register

  public
  def run(queue)
    while !stop?
      start = Time.now
      results = client.query(get_query())
      latest_tracking_field_value = nil
      if results && results.first
        results.each do |result|
          event = LogStash::Event.new()
          decorate(event)
          @sfdc_fields.each do |field|
            field_type = @sfdc_field_types[field]
            value = result.send(field)
            event_key = @to_underscores ? underscore(field) : field
            unless value.nil?
              case field_type
              when 'datetime', 'date'
                event.set(event_key, format_time(value))
              else
                event.set(event_key, value)
              end
            end
          end
          queue << event
          unless @tracking_field.nil?
            latest_tracking_field_value = result[@tracking_field]
          end
        end # loop sObjects
      end

      unless @tracking_field_value_file.nil?
        unless latest_tracking_field_value.nil?
          @logger.debug("Writing latest tracking field value " + latest_tracking_field_value + " to " + @tracking_field_value_file)
          File.write(@tracking_field_value_file, latest_tracking_field_value)
        else
          @logger.debug("No tracking field value found in result, not updating " + @tracking_field_value_file)
        end
      end

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
        end
        Stud.stoppable_sleep(sleeptime) { stop? }
      end  # end interval check
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
      :password       => @password.value,
      :security_token => @security_token.value,
      :client_id      => @client_id,
      :client_secret  => @client_secret.value,
      :timeout        => @timeout
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
    return options
  end

  private
  def get_query()
    sfdc_fields = @sfdc_fields.dup
    unless @tracking_field.nil?
      unless sfdc_fields.include?(@tracking_field)
        sfdc_fields << [@tracking_field]
      end
    end
    query = ["SELECT", sfdc_fields.join(','),
             "FROM", @sfdc_object_name]
    where = []
    unless @sfdc_filters.empty?
      append_to_where_clause(@sfdc_filters, where)
    end
    unless @changed_data_filter.nil?
      if File.exist?(@tracking_field_value_file)
        last_tracking_field_value = File.read(@tracking_field_value_file)
        changed_data_filter_interpolated = @changed_data_filter % { :last_tracking_field_value => last_tracking_field_value }
        append_to_where_clause(changed_data_filter_interpolated, where)
      end
    end
    query << where
    unless @tracking_field.nil?
      query << ["ORDER BY", @tracking_field, "ASC"]
    end
    query_str = query.flatten.join(" ")
    @logger.debug? && @logger.debug("SFDC Query", :query => query_str)
    return query_str
  end

  def append_to_where_clause(changed_data_filter_interpolated, where)
    if where.empty?
      where << ["WHERE"]
    else
      where << ["AND"]
    end
    where << [changed_data_filter_interpolated]
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

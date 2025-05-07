require "logstash/devutils/rspec/spec_helper"
require "logstash/inputs/salesforce"
require "vcr"
require 'json'

RSpec.describe LogStash::Inputs::Salesforce do
  describe "inputs/salesforce" do
    let(:options) do
      {
        "client_id" => "",
        "client_secret" => ::LogStash::Util::Password.new("secret-key"),
        "username" => "",
        "password" => ::LogStash::Util::Password.new("secret-password"),
        "security_token" => ::LogStash::Util::Password.new("secret-token"),
        "sfdc_object_name" => ""
      }
    end
    let(:input) { LogStash::Inputs::Salesforce.new(options) }
    subject { input }

    it "should convert to lowercase with underscores" do
      camel_cased_words = ['CleanStatus','CreatedBy',
                           'of_Open_Opp_related_account__c',
                           'USAField','ABCD_ABCDE_Threshold__c']
      underscore_words = ['clean_status','created_by',
                          'of_open_opp_related_account__c',
                          'usa_field','abcd_abcde_threshold__c']

      camel_cased_words.zip(underscore_words).each do |c,u|
        expect(subject.send(:underscore,c)).to eq(u)
      end
    end

    context "add fields and filters" do
      let(:options) do
        {
          "client_id" => "",
          "client_secret" => ::LogStash::Util::Password.new("secret-key"),
          "username" => "",
          "password" => ::LogStash::Util::Password.new("secret-password"),
          "security_token" => ::LogStash::Util::Password.new("secret-token"),
          "sfdc_object_name" => "Lead",
          "sfdc_fields" => ["Something"]
        }
      end
      let(:input) { LogStash::Inputs::Salesforce.new(options) }

      it "should build a query" do
        expect(subject.send(:get_query)).to eq('SELECT Something FROM Lead')
      end
    end

    context "describe Lead object" do
      VCR.configure do |config|
        config.cassette_library_dir = File.join(File.dirname(__FILE__), '..', 'fixtures', 'vcr_cassettes')
        config.hook_into :webmock
        config.before_record do |i|
          if i.response.body.encoding.to_s == 'ASCII-8BIT'
            # required because sfdc doesn't send back the content encoding and it
            # confuses the yaml parser
            json_body = JSON.load(i.response.body.encode("ASCII-8BIT").force_encoding("utf-8"))
            i.response.body = json_body.to_json
            i.response.update_content_length_header
          end
        end
      end
      let(:options) do
        {
          "client_id" => "",
          "client_secret" => ::LogStash::Util::Password.new("secret-key"),
          "username" => "",
          "password" => ::LogStash::Util::Password.new("secret-password"),
          "security_token" => ::LogStash::Util::Password.new("secret-token"),
          "sfdc_object_name" => "Lead"
        }
      end
      let(:input) { LogStash::Inputs::Salesforce.new(options) }
      let(:expected_fields_result) { ["Id", "IsDeleted",
                                      "LastName", "FirstName", "Salutation"] }
      let(:expected_types_result) { [["FirstName", "string"],
                                     ["Id", "id"],
                                     ["IsDeleted", "boolean"],
                                     ["LastName", "string"],
                                     ["Salutation", "picklist"]] }
      subject { input }
      it "loads the Lead object fields" do
        VCR.use_cassette("describe lead object",:decode_compressed_response => true) do
          subject.register
          expect(subject.instance_variable_get(:@sfdc_field_types)).to match_array(expected_types_result)
          expect(subject.instance_variable_get(:@sfdc_fields)).to match_array(expected_fields_result)
        end
      end
      context "load Lead objects" do
        let(:options) do
          {
            "client_id" => "",
            "client_secret" => ::LogStash::Util::Password.new("secret-key"),
            "username" => "",
            "password" => ::LogStash::Util::Password.new("secret-password"),
            "security_token" => ::LogStash::Util::Password.new("secret-token"),
            "sfdc_object_name" => "Lead",
            "sfdc_fields" => ["Id", "IsDeleted", "LastName", "FirstName", "Salutation"],
            "sfdc_filters" => "Email LIKE '%@elastic.co'"
          }
        end
        let(:input) { LogStash::Inputs::Salesforce.new(options) }
        subject { input }
        let(:queue) { [] }
        it "loads some lead records" do
          VCR.use_cassette("load some lead objects", :decode_compressed_response => true) do
            subject.register
            subject.run(queue)
            expect(queue.length).to eq(3)
            e = queue.pop
            expected_fields_result.each do |f|
              expect(e.to_hash).to include(f)
            end
          end
        end
      end
    end

    context "use sfdc instance url" do
      VCR.configure do |config|
        config.cassette_library_dir = File.join(File.dirname(__FILE__), '..', 'fixtures', 'vcr_cassettes')
        config.hook_into :webmock
        config.before_record do |i|
          if i.response.body.encoding.to_s == 'ASCII-8BIT'
            # required because sfdc doesn't send back the content encoding and it
            # confuses the yaml parser
            json_body = JSON.load(i.response.body.encode("ASCII-8BIT").force_encoding("utf-8"))
            i.response.body = json_body.to_json
            i.response.update_content_length_header
          end
        end
      end
      let(:options) do
        {
          "client_id" => "",
          "client_secret" => ::LogStash::Util::Password.new("secret-key"),
          "username" => "",
          "password" => ::LogStash::Util::Password.new("secret-password"),
          "security_token" => ::LogStash::Util::Password.new("secret-token"),
          "sfdc_instance_url" => "my-domain.my.salesforce.com",
          "sfdc_object_name" => "Lead"
        }
      end
      let (:input) { LogStash::Inputs::Salesforce.new(options) }
      let(:expected_fields_result) { ["Id", "IsDeleted",
                                      "LastName", "FirstName", "Salutation"] }
      let(:expected_types_result) { [["FirstName", "string"],
                                     ["Id", "id"],
                                     ["IsDeleted", "boolean"],
                                     ["LastName", "string"],
                                     ["Salutation", "picklist"]] }
      subject { input }
      it "logs into sfdc instance url" do
        VCR.use_cassette("login into mydomain", :decode_compressed_response => true) do
          subject.register
          expect(subject.instance_variable_get(:@sfdc_field_types)).to match_array(expected_types_result)
          expect(subject.instance_variable_get(:@sfdc_fields)).to match_array(expected_fields_result)
        end
      end
      context "...but not use_test_sandbox" do
        let(:options) do
          {
            "client_id" => "",
            "client_secret" => ::LogStash::Util::Password.new("secret-key"),
            "username" => "",
            "password" => ::LogStash::Util::Password.new("secret-password"),
            "security_token" => ::LogStash::Util::Password.new("secret-token"),
            "sfdc_instance_url" => "my-domain.my.salesforce.com",
            "sfdc_object_name" => "Lead",
            "use_test_sandbox" => true
          }
        end
        let (:input) { LogStash::Inputs::Salesforce.new(options) }
        subject { input }
        it "should raise a LogStash::ConfigurationError" do
          expect { subject.register }.to raise_error(::LogStash::ConfigurationError)
        end
      end
    end

    context "use Tooling Api" do
      VCR.configure do |config|
        config.cassette_library_dir = File.join(File.dirname(__FILE__), '..', 'fixtures', 'vcr_cassettes')
        config.hook_into :webmock
        config.before_record do |i|
          if i.response.body.encoding.to_s == 'ASCII-8BIT'
            # required because sfdc doesn't send back the content encoding and it
            # confuses the yaml parser
            json_body = JSON.load(i.response.body.encode("ASCII-8BIT").force_encoding("utf-8"))
            i.response.body = json_body.to_json
            i.response.update_content_length_header
          end
        end
      end
      let(:options) do
        {
          "api_version" => "52.0",
          "client_id" => "",
          "client_secret" => ::LogStash::Util::Password.new("secret-key"),
          "username" => "",
          "password" => ::LogStash::Util::Password.new("secret-password"),
          "security_token" => ::LogStash::Util::Password.new("secret-token"),
          "use_tooling_api" => true,
          "sfdc_object_name" => "ApexTestRunResult"
        }
      end
      let(:input) { LogStash::Inputs::Salesforce.new(options) }
      subject { input }
      it "should use the Tooling Api Query resource path" do
        VCR.use_cassette("describe apex test run result object", :decode_compressed_response => true) do
          subject.register
          expect(subject.send(:client).send(:api_path, "query")).to eq('/services/data/v52.0/tooling/query')
        end
      end
    end

    context "run continuously at interval" do
      VCR.configure do |config|
        config.cassette_library_dir = File.join(File.dirname(__FILE__), '..', 'fixtures', 'vcr_cassettes')
        config.hook_into :webmock
        config.before_record do |i|
          if i.response.body.encoding.to_s == 'ASCII-8BIT'
            # required because sfdc doesn't send back the content encoding and it
            # confuses the yaml parser
            json_body = JSON.load(i.response.body.encode("ASCII-8BIT").force_encoding("utf-8"))
            i.response.body = json_body.to_json
            i.response.update_content_length_header
          end
        end
      end
      let(:options) do
        {
          "client_id" => "",
          "client_secret" => ::LogStash::Util::Password.new("secret-key"),
          "username" => "",
          "password" => ::LogStash::Util::Password.new("secret-password"),
          "security_token" => ::LogStash::Util::Password.new("secret-token"),
          "use_tooling_api" => false,
          "sfdc_object_name" => "Lead",
          "sfdc_fields" => ["Id", "IsDeleted", "LastName", "FirstName", "Salutation"],
          "sfdc_filters" => "Email LIKE '%@elastic.co'",
          "interval" => 3
        }
      end
      let(:input) { LogStash::Inputs::Salesforce.new(options) }
      subject { input }
      let(:queue) { [] }
      it "loads some lead records" do
        VCR.use_cassette("load some lead objects twice", :decode_compressed_response => true) do
          subject.register
          # Run a background thread to set the stop flag after 7 seconds, i.e. after the second run of the plugin
          thr = Thread.new {
            sleep(4)  # more than 3, less than 6
            subject.do_stop
          }
          subject.run(queue)
          thr.join
          expect(queue.length).to eq(8) # 3 + 5
        end
      end
    end
  end
end

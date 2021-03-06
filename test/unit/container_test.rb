require_relative '../test_helper'

class Aggregate::ContainerTest < ActiveSupport::TestCase

  class ActiveRecordStub
    # Faking out active record things to get the large text field to work.
    def self.reflections
      {}
    end

    def self.has_many(*args)
      @has_many_args ||= []
      @has_many_args << args
    end

    def self.validate(*args)
      @validate_args ||= []
      @validate_args << args
    end

    def self.before_save(*args)
      @before_save ||= []
      @before_save << args
    end

    def reload
      @reload_called = true
    end
  end

  class TestAddress < Aggregate::Base
    attribute :full_name,    :string, default: "default_full_name"
    attribute :address_one,  :string
    attribute :address_two,  :string
    attribute :zip,          :string
    attribute :phone_number, :PhoneNumber

    validate :do_validation
    def do_validation
      errors.add :full_name, "cannot be Murphy" if full_name == "Murphy"
    end
  end

  class TestShippingRecord < Aggregate::Base
    attribute :tracking_number,     :string, default: -> { "default_tracking_number" }, required: true
    attribute :ship_from,           "Aggregate::ContainerTest::TestAddress", force_validation: true
    attribute :ship_to,             "Aggregate::ContainerTest::TestAddress"
    attribute :weight_in_ounces,    :integer, required: true
    attribute :shipping_method,     :enum, limit: [:UPS, :UsPostal]
    attribute :signature_required,  :boolean
    attribute :shipped_at,          :datetime
    attribute :postage_due,         :decimal

    validates_numericality_of :postage_due, greater_than_or_equal_to: 0, less_than_or_equal_to: 100
  end

  class TestPurchase < ActiveRecordStub
    include Aggregate::Container

    attr_accessor :fixup1_called, :fixup2_called, :value_at_fixup1, :upgraded_from_schema_version, :value_at_upgrade

    # Overrides value from Aggregate::Container
    attr_accessor :aggregate_store
    attr_accessor :aggregate_field_store

    def initialize(aggregate_store_json = nil, aggregate_field_store_json = nil)
      @aggregate_store = aggregate_store_json
      @aggregate_field_store = aggregate_field_store_json
    end

    set_callback(:aggregate_load, :after, :fixup1)
    def fixup1
      if first_shipment._?.tracking_number == "9999"
        first_shipment.tracking_number = "8888"
      end

      @fixup1_called = true
    end

    set_callback(:aggregate_load) do |obj|
      obj.fixup2_called = true
    end

    aggregate_schema_version "2.0", :fix_aggregate_schema
    def fix_aggregate_schema(current_version)
      @upgraded_from_schema_version ||= []
      @upgraded_from_schema_version << "#{current_version.inspect}"
      @value_at_upgrade = test_string
    end

    aggregate_attribute :test_string,      :string
    aggregate_attribute :first_shipment,   "Aggregate::ContainerTest::TestShippingRecord"
    aggregate_attribute :second_shipment,  "Aggregate::ContainerTest::TestShippingRecord"
  end

  class TestPurchaseNoVersion < ActiveRecordStub
    include Aggregate::Container

    attr_accessor :fixup1_called, :fixup2_called, :value_at_fixup1, :upgraded_from_schema_version, :value_at_upgrade

    # Overrides value from Aggregate::Container
    attr_accessor :aggregate_store

    def initialize(json = nil)
      @aggregate_store = json
    end

    set_callback(:aggregate_load, :after, :fixup1)
    def fixup1
      if first_shipment._?.tracking_number == "9999"
        first_shipment.tracking_number = "8888"
      end

      @fixup1_called = true
    end

    set_callback(:aggregate_load) do |obj|
      obj.fixup2_called = true
    end

    aggregate_attribute :test_string,      :string
    aggregate_attribute :first_shipment,   "Aggregate::ContainerTest::TestShippingRecord"
    aggregate_attribute :second_shipment,  "Aggregate::ContainerTest::TestShippingRecord"
  end

  context "sample_data" do
    setup do
      @aggregate_container_options = TestPurchase.aggregate_container_options.dup
    end
    
    teardown do
      TestPurchase.aggregate_container_options = @aggregate_container_options
    end

    context "initialization" do
      
      should "have configured the active record settings correctly" do
        # Configure a large text field.
        assert_equal [[:large_text_fields, { inverse_of: :owner, as: :owner, dependent: :destroy, autosave: true, class_name: "LargeTextField::NamedTextValue" }]], TestPurchase.instance_eval('@has_many_args')
        assert_equal [[:validate_large_text_fields], [:validate_aggregates]], TestPurchase.instance_eval('@validate_args')
        assert_equal [[:write_large_text_field_changes]], TestPurchase.instance_eval('@before_save')
      end

      should "have a configuration with defaults" do
        assert_nil TestPurchase.aggregate_container_options[:use_storage_field]
        assert_false TestPurchase.aggregate_container_options[:use_large_text_field_as_failover]
      end

      should "know when using a storage field or a large text field" do
        assert_false TestPurchase.new.uses_aggregate_storage_field?
        TestPurchase.aggregate_container_options[:use_storage_field] = :aggregate_field_store
        assert TestPurchase.new.uses_aggregate_storage_field?
      end

      should "know which field the aggregate data is stored in" do
        assert_equal :aggregate_store, TestPurchase.new.aggregate_storage_field
        TestPurchase.aggregate_container_options[:use_storage_field] = :aggregate_field_store
        assert_equal :aggregate_field_store, TestPurchase.new.aggregate_storage_field        
      end

      should "know when to failover to large_text_field" do
        assert_false TestPurchase.new.failover_to_large_text_field?

        TestPurchase.aggregate_container_options[:use_storage_field] = :aggregate_field_store
        assert_false TestPurchase.new.failover_to_large_text_field?

        TestPurchase.aggregate_container_options[:use_large_text_field_as_failover] = true
        assert TestPurchase.new.failover_to_large_text_field?
        
        TestPurchase.aggregate_container_options[:use_storage_field] = nil
        assert_false TestPurchase.new.failover_to_large_text_field?
      end
    end

    context "error_messages_for methods" do
      should "support self_and_descendants_from_active_record" do
        assert_equal [TestShippingRecord], TestShippingRecord.self_and_descendants_from_active_record
      end

      should "support human name" do
        assert_equal "Aggregate::containertest::testshippingrecord", TestShippingRecord.human_name
      end

      should "support human_attribute_name" do
        assert_equal "Cheese burger", TestShippingRecord.human_attribute_name(:cheese_burger)
      end
    end

    context "basic construction" do
      should "be able to construct an instance using the assignment operator" do
        @doc = TestPurchase.new
        assert_nil @doc.first_shipment
        @doc.first_shipment = TestShippingRecord.new(tracking_number: '1245', weight_in_ounces: 5)
        assert_equal '1245', @doc.first_shipment.tracking_number
        assert_equal 5,      @doc.first_shipment.weight_in_ounces
      end

      should "support build instead of assign" do
        @doc = TestPurchase.new
        assert_nil @doc.first_shipment
        result = @doc.build_first_shipment(tracking_number: '1245', weight_in_ounces: 5)
        assert_equal "Aggregate::ContainerTest::TestShippingRecord", result.class.name
        assert_equal '1245', @doc.first_shipment.tracking_number
        assert_equal 5,      @doc.first_shipment.weight_in_ounces
      end

      should "support nested attributes" do
        @doc = TestPurchase.new
        assert_nil @doc.first_shipment
        @doc.build_first_shipment(tracking_number: '1245', weight_in_ounces: 5)
        @doc.first_shipment.build_ship_from(full_name: 'Lisa Smith', address_one: '1812 Clearview Road', address_two: '', zip: '93101')
        assert_equal 'Lisa Smith', @doc.first_shipment.ship_from.full_name
      end

      should "support building with nested attributes" do
        @doc = TestPurchase.new
        @doc.build_first_shipment(
          tracking_number: '1245',
          weight_in_ounces: 5,
          ship_from: {
            full_name: 'Lisa Smith',
            address_one: '1812 Clearview Road',
            address_two: '',
            zip: '93101'
          })

        assert_equal '1245',       @doc.first_shipment.tracking_number
        assert_equal 5,            @doc.first_shipment.weight_in_ounces
        assert_equal 'Lisa Smith', @doc.first_shipment.ship_from.full_name
      end

      should "support building with strings instead of symbols" do
        @doc = TestPurchase.new
        @doc.build_first_shipment(
          'tracking_number' => '1245',
          'weight_in_ounces' => 5,
          'ship_from' => {
            'full_name' => 'Lisa Smith',
            'address_one' => '1812 Clearview Road',
            'address_two' => '',
            'zip' => '93101'
          })

        assert_equal '1245',       @doc.first_shipment.tracking_number
        assert_equal 5,            @doc.first_shipment.weight_in_ounces
        assert_equal 'Lisa Smith', @doc.first_shipment.ship_from.full_name

        assert_nil @doc.second_shipment
      end

      should "support default arguments" do
        @doc = TestPurchase.new
        @doc.build_first_shipment
        assert_equal 'default_tracking_number', @doc.first_shipment.tracking_number

        @doc.first_shipment.build_ship_from
        assert_equal 'default_full_name', @doc.first_shipment.ship_from.full_name
      end

      should "be able to find the root_aggregate_owner" do
        @doc = TestPurchase.new
        @doc.build_first_shipment(
          tracking_number: '1245',
          weight_in_ounces: 5,
          ship_from: {
            full_name: 'Lisa Smith',
            address_one: '1812 Clearview Road',
            address_two: '',
            zip: '93101'
          })

        assert_equal @doc, @doc.first_shipment.root_aggregate_owner
        assert_equal @doc, @doc.first_shipment.ship_from.root_aggregate_owner
      end
    end

    context "loading" do
      setup do
        @json = {
          'first_shipment' => {
            'tracking_number' => '1245',
            'weight_in_ounces' => 5,
            'ship_from' => {
              'full_name' => 'Lisa Smith',
              'address_one' => '1812 Clearview Road',
              'address_two' => '',
              'zip' => '93101'
            }
          }
        }.to_json
      end

      should "load from the large_text_field when no storage_field is specified" do
        @doc = TestPurchase.new(@json, nil)
        assert_false @doc.uses_aggregate_storage_field?
        assert_nil @doc.aggregate_field_store
        assert_equal @json, @doc.aggregate_store

        assert_equal '1245',       @doc.first_shipment.tracking_number
        assert_equal 5,            @doc.first_shipment.weight_in_ounces
        assert_equal 'Lisa Smith', @doc.first_shipment.ship_from.full_name        
      end

      should "load from the storage_field when it's specified" do
        assert_nil TestPurchase.aggregate_container_options[:use_storage_field]
        TestPurchase.aggregate_container_options[:use_storage_field] = :aggregate_field_store
        @doc = TestPurchase.new(nil, @json)
        assert @doc.uses_aggregate_storage_field?
        assert_nil @doc.aggregate_store
        assert_equal @json, @doc.aggregate_field_store

        assert_equal 5,            @doc.first_shipment.weight_in_ounces
        assert_equal 'Lisa Smith', @doc.first_shipment.ship_from.full_name                
      end

      should "load from the large_text_field when storage_field and failover are enabled but storage_field is blank" do
        assert_nil TestPurchase.aggregate_container_options[:use_storage_field]
        assert_false TestPurchase.aggregate_container_options[:use_large_text_field_as_failover]
        TestPurchase.aggregate_container_options[:use_storage_field] = :aggregate_field_store
        TestPurchase.aggregate_container_options[:use_large_text_field_as_failover] = true
        
        @doc = TestPurchase.new(@json, nil)
        assert @doc.uses_aggregate_storage_field?
        assert @doc.failover_to_large_text_field?
        assert_nil @doc.aggregate_field_store
        assert_equal @json, @doc.aggregate_store
        
        assert_equal 'Lisa Smith', @doc.first_shipment.ship_from.full_name
      end
    end

    should "report when any attributes have been changed" do
      json = {
        'first_shipment' => {
          'tracking_number' => '1245',
          'weight_in_ounces' => 5,
          'ship_from' => {
            'full_name' => 'Lisa Smith',
            'address_one' => '1812 Clearview Road',
            'address_two' => '',
            'zip' => '93101'
          }
        }
      }.to_json

      @doc = TestPurchase.new(json)

      assert_equal '1245',       @doc.first_shipment.tracking_number
      assert_equal 5,            @doc.first_shipment.weight_in_ounces
      assert_equal 'Lisa Smith', @doc.first_shipment.ship_from.full_name

      assert !@doc.first_shipment_changed?
      assert !@doc.first_shipment.tracking_number_changed?

      @doc.first_shipment.tracking_number = '12345'
      assert_equal '12345', @doc.first_shipment.tracking_number

      assert @doc.first_shipment.tracking_number_changed?
      assert @doc.first_shipment_changed?
    end

    context "saving data" do
      should "marshal to json" do
        json = {
          'first_shipment' => {
            'tracking_number' => '1245',
            'weight_in_ounces' => 5,
            'ship_from' => {
              'full_name' => 'Lisa Smith',
              'address_one' => '1812 Clearview Road',
              'address_two' => '',
              'zip' => '93101'
            }
          }
        }.to_json
        @doc = TestPurchase.new(json)

        expected = {
            "data_schema_version" => "2.0",
            "test_string"         => nil,
            "second_shipment"     => nil,
            "first_shipment"      => {
                "ship_from" => {
                    "zip"          => "93101",
                    "address_two"  => "",
                    "address_one"  => "1812 Clearview Road",
                    "full_name"    => "Lisa Smith"
                },
                "tracking_number"    => "1245",
                "weight_in_ounces"   => 5
            }
        }
        assert_equal expected, @doc.to_store

        @doc.write_aggregates
        assert_equal expected, ActiveSupport::JSON.decode(@doc.aggregate_store)
      end

      should "use an alternative field for storage if specified by the config" do
        json = {
          'first_shipment' => {
            'tracking_number' => '1245',
            'weight_in_ounces' => 5,
            'ship_from' => {
              'full_name' => 'Lisa Smith',
              'address_one' => '1812 Clearview Road',
              'address_two' => '',
              'zip' => '93101'
            }
          }
        }.to_json
        assert_nil TestPurchase.aggregate_container_options[:use_storage_field]
        TestPurchase.aggregate_container_options[:use_storage_field] = :aggregate_field_store
        @doc = TestPurchase.new(nil, json)
        assert_nil @doc.aggregate_store
        
        expected = {
            "data_schema_version" => "2.0",
            "test_string"         => nil,
            "second_shipment"     => nil,
            "first_shipment"      => {
                "ship_from" => {
                    "zip"          => "93101",
                    "address_two"  => "",
                    "address_one"  => "1812 Clearview Road",
                    "full_name"    => "Lisa Smith"
                },
                "tracking_number"    => "1245",
                "weight_in_ounces"   => 5
            }
        }
        assert_equal expected, @doc.to_store
        @doc.write_aggregates
        assert_equal expected, ActiveSupport::JSON.decode(@doc.aggregate_field_store)
      end


      should "write an empty string for classes at default values" do
        @doc = TestPurchase.new("")
        @doc.write_aggregates

        assert_equal "", @doc.aggregate_store
      end

      should "write an empty string if a field changes back to an empty value" do
        @doc = TestPurchaseNoVersion.new("")
        @doc.first_shipment = TestShippingRecord.new(tracking_number: '1245', weight_in_ounces: 5)
        @doc.write_aggregates
        assert_not_equal "", @doc.aggregate_store

        @doc.first_shipment = nil
        @doc.write_aggregates
        assert_equal "", @doc.aggregate_store
      end

      should "not write an empty string if a field changes back to an empty value when there is a schema version" do
        @doc = TestPurchase.new("")
        @doc.first_shipment = TestShippingRecord.new(tracking_number: '1245', weight_in_ounces: 5)
        @doc.write_aggregates
        assert_not_equal "", @doc.aggregate_store

        @doc.first_shipment = nil
        @doc.write_aggregates
        assert_not_equal "", @doc.aggregate_store
      end
    end

    context "builtin types" do
      context "enum" do
        should "support load save and assign" do
          json = {
            'first_shipment' => {
              'tracking_number' => '1245',
              'weight_in_ounces' => 5,
              'shipping_method' => 'UsPostal',
              'ship_from' => {
                'full_name' => 'Lisa Smith',
                'address_one' => '1812 Clearview Road',
                'address_two' => '',
                'zip' => '93101'
              }
            }
          }.to_json
          @doc = TestPurchase.new(json)

          assert_equal :UsPostal, @doc.first_shipment.shipping_method

          @doc.first_shipment.shipping_method = :UPS

          expected = {
            "data_schema_version" => "2.0",
            "test_string"         => nil,
            "second_shipment"     => nil,
            "first_shipment"      => {
                "ship_from" => {
                    "zip"          => "93101",
                    "address_two"  => "",
                    "address_one"  => "1812 Clearview Road",
                    "full_name"    => "Lisa Smith"
                },
                "tracking_number"    => "1245",
                "weight_in_ounces"   => 5,
                "shipping_method"    => "UPS"
            }
          }
          assert_equal expected, @doc.to_store

          # Don't explode when assigned an empty string.
          @doc.first_shipment.shipping_method = ""
          @doc.first_shipment.postage_due = 10

          assert @doc.first_shipment.valid?, @doc.first_shipment.errors.full_messages.inspect
          @doc.to_store
        end
      end
      context "boolean" do
        should "support load save and assign" do
          json = {
            'first_shipment' => {
              'tracking_number' => '1245',
              'weight_in_ounces' => 5,
              'shipping_method' => 'UsPostal',
              'signature_required' => false,
              'ship_from' => {
                'full_name' => 'Lisa Smith',
                'address_one' => '1812 Clearview Road',
                'address_two' => '',
                'zip' => '93101'
              }
            }
          }.to_json
          @doc = TestPurchase.new(json)

          assert_equal false, @doc.first_shipment.signature_required

          [true, '1', 't', 'T', 'TRUE', @doc].each do |v|
            @doc.first_shipment.signature_required = v
            assert_equal true, @doc.first_shipment.signature_required, v.inspect
          end

          [false, '0', 'f', 'F', 'false'].each do |v|
            @doc.first_shipment.signature_required = v
            assert_equal false, @doc.first_shipment.signature_required, v.inspect
          end

          [nil, ''].each do |v|
            @doc.first_shipment.signature_required = v
            assert_nil @doc.first_shipment.signature_required, v.inspect
          end

          @doc.first_shipment.signature_required = true

          expected = {
            "data_schema_version" => "2.0",
            "test_string"         => nil,
            "second_shipment"     => nil,
            "first_shipment"      => {
                "ship_from" => {
                    "zip" => "93101",
                    "address_two" => "",
                    "address_one" => "1812 Clearview Road",
                    "full_name" => "Lisa Smith"
                },
                "tracking_number" => "1245",
                "weight_in_ounces" => 5,
                "shipping_method" => "UsPostal",
                "signature_required" => true,
            }
          }
          assert_equal expected, @doc.to_store
        end
      end
      context "datetime" do
        setup do
          stub(Time).now { Time.zone.local(2008, 3, 10) }
        end

        should "support convert to the current time zone when loading" do
          json = {
            'first_shipment' => {
              'tracking_number' => '1245',
              'weight_in_ounces' => 5,
              'shipping_method' => 'UsPostal',
              'signature_required' => false,
              'shipped_at' => "2012/04/18 17:50:08 -0700",
              'ship_from' => {
                'full_name' => 'Lisa Smith',
                'address_one' => '1812 Clearview Road',
                'address_two' => '',
                'zip' => '93101'
              }
            }
          }.to_json

          begin
            old_time_zone, Time.zone = Time.zone, "Eastern Time (US & Canada)"
            @doc = TestPurchase.new(json)
            assert_equal "04/18/12   8:50 PM", @doc.first_shipment.shipped_at.to_s
            assert_equal "Thu, 19 Apr 2012 00:50:08 -0000", @doc.to_store["first_shipment"]["shipped_at"]
          ensure
            Time.zone = old_time_zone
          end

          begin
            old_time_zone, Time.zone = Time.zone, "Pacific Time (US & Canada)"
            @doc = TestPurchase.new(json)
            assert_equal "04/18/12   5:50 PM", @doc.first_shipment.shipped_at.to_s

            assert_equal "Thu, 19 Apr 2012 00:50:08 -0000", @doc.to_store["first_shipment"]["shipped_at"]
          ensure
            Time.zone = old_time_zone
          end
        end

        should "handle assignment in various forms" do
          @doc = TestPurchase.new
          @doc.build_first_shipment
          assert_nil @doc.first_shipment.shipped_at
          @doc.first_shipment.shipped_at = Time.now

          assert_equal "03/10/08  12:00 AM", @doc.first_shipment.shipped_at.to_s

          @doc.first_shipment.shipped_at = "2012-04-26"
          assert_equal "04/26/12  12:00 AM", @doc.first_shipment.shipped_at.to_s
          assert_equal "Thu, 26 Apr 2012 07:00:00 -0000", @doc.to_store["first_shipment"]["shipped_at"]

          @doc.first_shipment.shipped_at = ''
          assert_nil @doc.first_shipment.shipped_at
          assert_nil @doc.to_store["first_shipment"]["shipped_at"]

          @doc.first_shipment.shipped_at = 'notvalid'
          assert_nil @doc.first_shipment.shipped_at
          assert_nil @doc.to_store["first_shipment"]["shipped_at"]
        end
      end
      context "decimal" do
        should "support load save and assign" do
          json = {
            'first_shipment' => {
              'tracking_number' => '1245',
              'weight_in_ounces' => 5,
              'shipping_method' => 'UsPostal',
              'postage_due' => '1001.10',
              'ship_from' => {
                'full_name' => 'Lisa Smith',
                'address_one' => '1812 Clearview Road',
                'address_two' => '',
                'zip' => '93101'
              }
            }
          }.to_json
          @doc = TestPurchase.new(json)

          assert_equal '1001.1', @doc.first_shipment.postage_due.to_s

          @doc.first_shipment.postage_due = '50.20'

          expected = {
            "data_schema_version" => "2.0",
            "test_string"         => nil,
            "second_shipment"     => nil,
            "first_shipment"      => {
                "ship_from" => {
                    "zip" => "93101",
                    "address_two" => "",
                    "address_one" => "1812 Clearview Road",
                    "full_name" => "Lisa Smith"
                },
                "tracking_number" => "1245",
                "weight_in_ounces" => 5,
                "shipping_method" => "UsPostal",
                "postage_due" => '50.2',
            }
          }
          assert_equal expected, @doc.to_store
        end
      end
    end

    context "validations" do
      setup do
        @doc = TestPurchase.new
        @doc.build_first_shipment(
          tracking_number: '1245',
          weight_in_ounces: 5,
          postage_due: 10.0,
          ship_from: {
            full_name: 'Lisa Smith',
            address_one: '1812 Clearview Road',
            address_two: '',
            zip: '93101'
          })
      end

      should "enforce required fields" do
        @doc.build_first_shipment(
          tracking_number: '1245',
          postage_due: 10.0,
          ship_from: {
            full_name: 'Lisa Smith',
            address_one: '1812 Clearview Road',
            address_two: '',
            zip: '93101'
          })

        assert !@doc.first_shipment.valid?
        assert_equal ["Weight in ounces must be set"], @doc.first_shipment.errors.full_messages
      end

      should "support validations on the model" do
        @doc.first_shipment.ship_from.full_name = "Murphy"
        assert !@doc.first_shipment.ship_from.valid?
        assert_equal ["Full name cannot be Murphy"], @doc.first_shipment.ship_from.errors.full_messages
        assert_equal "cannot be Murphy",             @doc.first_shipment.ship_from.errors[:full_name].first

        assert !@doc.first_shipment.valid?
        assert_equal ["Ship from Full name cannot be Murphy"],  @doc.first_shipment.errors.full_messages
        assert_equal "Full name cannot be Murphy",              @doc.first_shipment.errors[:ship_from].first
      end

      should "support rails validators" do
        @doc.first_shipment.postage_due = -1
        assert !@doc.first_shipment.valid?
        assert_equal ["Postage due must be greater than or equal to 0"], @doc.first_shipment.errors.full_messages
      end
    end

    context "callbacks" do
      should "fire callbacks when loaded" do
        json = {
          'first_shipment' => {
            'tracking_number' => '9999',
            'weight_in_ounces' => 5,
            'ship_from' => {
              'full_name' => 'Lisa Smith',
              'address_one' => '1812 Clearview Road',
              'address_two' => '',
              'zip' => '93101'
            }
          }
        }.to_json

        @doc = TestPurchase.new(json)
        assert !@doc.fixup1_called
        assert !@doc.fixup2_called

        # should have been able to change the value during the callback.
        assert_equal "8888", @doc.first_shipment.tracking_number
        assert @doc.fixup1_called
        assert @doc.fixup2_called
      end

      should "fire schema version callbacks if schema is missing" do
        json = {
          'first_shipment' => {
            'tracking_number' => '9999',
            'weight_in_ounces' => 5,
            'ship_from' => {
              'full_name' => 'Lisa Smith',
              'address_one' => '1812 Clearview Road',
              'address_two' => '',
              'zip' => '93101'
            }
          }
        }.to_json

        @doc = TestPurchase.new(json)
        @doc.first_shipment

        assert_equal ["nil"], @doc.upgraded_from_schema_version
        assert_equal "2.0", @doc.to_store["data_schema_version"]
      end

      should "fire schema version callbacks if schema does not match" do
        json = {
          'first_shipment' => {
            'tracking_number' => '9999',
            'weight_in_ounces' => 5,
            'ship_from' => {
              'full_name' => 'Lisa Smith',
              'address_one' => '1812 Clearview Road',
              'address_two' => '',
              'zip' => '93101'
            }
          },
          "data_schema_version" => "1.9"
        }.to_json

        @doc = TestPurchase.new(json)
        @doc.first_shipment

        assert_equal ["\"1.9\""], @doc.upgraded_from_schema_version
        assert_equal "2.0", @doc.to_store["data_schema_version"]
      end

      should "not fire schema version callbacks if schema matches" do
        json = {
          'first_shipment' => {
            'tracking_number' => '9999',
            'weight_in_ounces' => 5,
            'ship_from' => {
              'full_name' => 'Lisa Smith',
              'address_one' => '1812 Clearview Road',
              'address_two' => '',
              'zip' => '93101'
            }
          },
          "data_schema_version" => "2.0"
        }.to_json

        @doc = TestPurchase.new(json)
        @doc.first_shipment

        assert_nil @doc.upgraded_from_schema_version
      end

      should "not fire twice" do
        json = {
          'first_shipment' => {
            'tracking_number' => '9999',
            'weight_in_ounces' => 5,
            'ship_from' => {
              'full_name' => 'Lisa Smith',
              'address_one' => '1812 Clearview Road',
              'address_two' => '',
              'zip' => '93101'
            }
          },
          "data_schema_version" => "1.9"
        }.to_json

        @doc = TestPurchase.new(json)
        @doc.first_shipment

        assert_equal ["\"1.9\""], @doc.upgraded_from_schema_version
        @doc.upgraded_from_schema_version = nil

        @doc.second_shipment
        assert_nil @doc.upgraded_from_schema_version
      end

      should "pass the schema value and not the assigned value when performing the upgrade" do
        json = {
          'first_shipment' => {
            'tracking_number' => '6666',
            'weight_in_ounces' => 5,
            'ship_from' => {
              'full_name' => 'Lisa Smith',
              'address_one' => '1812 Clearview Road',
              'address_two' => '',
              'zip' => '93101'
            }
          },
          "test_string" => "initial value",
          "data_schema_version" => "1.9"
        }.to_json

        @doc = TestPurchase.new(json)
        @doc.first_shipment
        @doc.test_string = "assigned_value"

        assert_equal "initial value", @doc.value_at_upgrade
      end
    end

    should "forget cached aggregate store on reload" do
      @doc = TestPurchase.new
      @doc.aggregate_store = { "test_string" => "12345"}.to_json
      assert_nil @doc.first_shipment
      assert_equal "12345", @doc.test_string

      @doc.first_shipment = TestShippingRecord.new(tracking_number: '1245', weight_in_ounces: 5)
      assert_equal '1245', @doc.first_shipment.tracking_number

      @doc.aggregate_store = { "test_string" => "56789"}.to_json

      @doc.reload
      assert_nil @doc.first_shipment
      assert_equal true, @doc.instance_variable_get("@reload_called")
      assert_equal "56789", @doc.test_string
    end
  end
end

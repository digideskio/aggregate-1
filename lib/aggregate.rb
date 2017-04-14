require "aggregate/bitfield"

require "aggregate/attribute/base"
require "aggregate/attribute/builtin"
require "aggregate/attribute/string"
require "aggregate/attribute/integer"
require "aggregate/attribute/float"
require "aggregate/attribute/boolean"
require "aggregate/attribute/enum"
require "aggregate/attribute/date_time"
require "aggregate/attribute/decimal"
require "aggregate/attribute/nested_aggregate"
require "aggregate/attribute/schema_version"
require "aggregate/attribute/foreign_key"
require "aggregate/attribute/list"
require "aggregate/attribute/bitfield"

require "aggregate/engine"
require "aggregate/aggregate_store"
require "aggregate/attribute_handler"
require "aggregate/base"
require "aggregate/combined_string_field"
require "aggregate/container"

module Aggregate
  class << self
    attr_writer :configuration


    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset
      @configuration = Configuration.new
    end
  end

  class Configuration
    attr_accessor :keys_list

    def initialize
      # Should be a list made up of hashes that have:
      #   - keys : to encrypt/decrypt
      #
      # Example:
      #
      #  {
      #     key_2017_04_14: "\x11\xD2\xA2\x8F\x8E\xC9!i\xF8\xEEr\x03A\xF3\xA7QvY\x8F\xBCzw\xA7\xE3\xA7;\x86\xAE\xD3\x13\x9F/",
      #     key_2017_04_11: "\xCAE\x1F\xC7<W\xEA\xB4[\xE4'\xCA'\a\x17&\xF2I\x87\x1A\x17\x9B?\x86\xB1A\a%9\xEBZ@",
      #     key_2017_03_29: "#\x13G\xFA\xE5\"\xC0\xCAzL\xE7\x9F\xB0=[\x17>\xF33\xC2\x85\xBF\x16%\a\xE8z:]\xCA1D"
      #   }
      #
      # or just set to one key
      #
      #

      @keys_list = nil
    end
  end
end

require "nokogiri"

module ASM
  class WsMan
    class Parser
      # Parse a ws-man response element into a value
      #
      # Special-case handling exists for wsman:Selector responses which are used to
      # indicate job responses and for s:Subcode responses which are used in wsman faults.
      #
      # @api private
      # @param elem [Nokogiri::XML::Element]
      # @return [String]
      def self.parse_element(elem)
        if elem.namespaces.keys.include?("xmlns:wsman") && !(params = elem.xpath(".//wsman:Selector[@Name='InstanceID']")).empty?
          params.first.text
        elsif !(params = elem.xpath(".//s:Subcode")).empty? && params.children.size > 0
          params.children.map(&:text).join(", ")
        elsif elem.attributes["nil"] && elem.attributes["nil"].value == "true"
          nil
        else
          elem.text
        end
      end

      # Parse WS-Man invoke or get response into a Hash
      #
      # @api private
      # @param content [String] the WS-Man CLI response to invoke or get commands
      # @return [Hash]
      def self.parse(content, require_body=true)
        doc = Nokogiri::XML.parse(content, &:noblanks)
        body = doc.search("//s:Body")
        unless body.children.size == 1
          raise("Unexpected WS-Man Body: %s" % body.children) if require_body
          return nil
        end
        ret = {}
        response = body.children.first
        response.children.each do |e|
          key = snake_case(e.name).to_sym
          ret[key] = parse_element(e)
        end
        ret
      end

      # Parse WS-Man enumeration response into list of hashes
      #
      # @api private
      # @param content [String] the WS-Man CLI response to an enumerate command
      # @return [Array<Hash>]
      def self.parse_enumeration(content)
        responses = content.split("</s:Envelope>").map(&:strip).reject(&:empty?)

        # Check and return fault if found
        if responses.size == 1
          ret = parse(responses.first, false)
          return ret if ret
        end

        # Create an array of hashes containing each wsen:Item
        responses.flat_map do |xml|
          doc = Nokogiri::XML.parse(xml, &:noblanks)
          body = doc.search("//wsen:Items")
          next if body.children.empty?
          body.children.map do |elem|
            elem.children.inject({}) do |acc, e|
              key = snake_case(e.name).to_sym
              acc[key] = parse_element(e)
              acc
            end
          end
        end.compact
      end

      # Converts a ws-man parameter key into snake case
      #
      # Special case handling is included for various nouns that are usually (but
      # not always) capitalized such as ISO, MAC, FCOE, and WWNN>
      #
      # @param str [String] the wsman parameter key
      # @return [String]
      def self.snake_case(str)
        ret = str
        ret = ret.gsub(/ISO([A-Z]?)/) {"Iso%s" % $1}
        ret = ret.gsub(/MAC([A-Z]?)/) { "Mac%s" % $1}
        ret = ret.gsub(/PCI([A-Z]?)/) { "Pci%s" % $1}
        ret = ret.gsub(/BIOS([A-Z]?)/) { "Bios%s" % $1}
        ret = ret.gsub(/EFI([A-Z]?)/) {"Efi%s" % $1}
        ret = ret.gsub(/FC[oO]E([A-Z]?)/) {"Fcoe%s" % $1}
        ret = ret.gsub(/WWNN([A-Z]?)/) {"Wwnn%s" % $1}
        ret = ret.gsub(/iS[cC][sS][iI]([A-Z]?)/) {"Iscsi%s" % $1}
        ret = ret.gsub(/([A-Z]+)/) {"_%s" % $1.downcase}
        if ret =~ /^[_]+(.*)$/
          ret = $1
          ret = "%s%s" % [$1, ret] if str =~ /^([_]+)/
        end
        ret
      end

      # Search for the value in both the enum keys and values
      #
      # @param key [String] the enum name, used for error messaging only
      # @param enum [Hash] a hash of key/values. The values should be strings.
      # @param value [Object]
      # @return [String]
      # @raise [StandardError] if the value cannot be found in the enum
      def self.enum_value(key, enum, value, options={})
        options = {:strict => true}.merge(options)
        return enum[value] if enum[value]
        return value.to_s if enum.values.include?(value.to_s)
        return value unless options[:strict]
        allowed = enum.keys.map { |k| "%s (%s)" % [k.inspect, enum[k]]}.join(", ")
        raise("Invalid %s value: %s; allowed values are: %s" % [key.to_s, value, allowed])
      end

      # Convert known wsman properties to their expected format
      #
      # Converts known enum keys such as :share_type and :hash_type to their value.
      # Value is returned unmodified for other keys.
      #
      # @api private
      # @param key [Symbol] the property key, such as :share_type or :hash_type
      # @return [String]
      # @raise [StandardError] if an enum key has an unknown value
      def self.wsman_value(key, value)
        case key
        when :share_type
          enum_value(key, {:nfs => "0", :cifs => "2"}, value)
        when :hash_type
          enum_value(key, {:md5 => "1", :sha1 => "2"}, value)
        when :reboot_job_type
          enum_value(key, {:power_cycle => "1", :graceful => "2", :graceful_with_forced_shutdown => "3"}, value)
        when :shutdown_type
          enum_value(key, {:graceful => "0", :forced => "1"}, value)
        when :end_host_power_state
          enum_value(key, {:on => "0", :off => "1"}, value)
        when :export_use
          enum_value(key, {:default => "0", :clone => "1", :replace => "2"}, value)
        when :include_in_export
          enum_value(key, {:default => "0", :read_only => "1", :password_hash => "2",
                           :read_only_and_password_hash => "3"}, value)
        when :requested_state
          enum_value(key, {:on => "2", :off => "13"}, value)
        else
          value
        end
      end

      # Convert string to camel case
      #
      # @api private
      # @param str [String]
      # @param options [Hash]
      # @option options [Boolean] :capitalize whether to capitalize the final result
      # @return [String]
      def self.camel_case(str, options={})
        options = {:capitalize => false}.merge(options)
        ret = str.gsub(/_(.)/) {$1.upcase}
        ret[0] = ret[0].upcase if options[:capitalize]
        ret
      end

      # Convert a symbol to a ws-man parameter key
      #
      # @api private
      # @param sym [Symbol]
      # @return [String]
      def self.param_key(sym)
        return sym unless sym.is_a?(Symbol)

        case sym
        when :ip_address
          "IPAddress"
        when :source
          "source"
        when :instance_id
          "InstanceID"
        when :job_id
          "JobID"
        else
          camel_case(sym.to_s, :capitalize => true)
        end
      end

      # Convert a wsman response hash into a human-readable string.
      #
      # @example
      #     response = {:message => "Could not connect to share", :code => "XXX", :return_value => "2"}
      #     ASM::WsMan.response_string(response) #=> "Could not connect to share [code: XXX, return_value: 2]"
      #
      # @api private
      # @param response [Hash] ws-man response as a Hash, i.e. after calling {#parse} on the response.
      # @return [String]
      def self.response_string(response)
        copy = response.dup
        message = copy.delete(:message)
        message = copy.delete(:reason) unless message
        message = copy.delete(:job_status) unless message
        ret = copy.keys.map { |k| "%s: %s" % [k, copy[k]]}.join(", ")
        ret = "%s [%s]" % [message, ret] if message
        ret
      end
    end
  end
end

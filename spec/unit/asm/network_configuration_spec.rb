require 'spec_helper'
require 'asm/network_configuration'

describe ASM::NetworkConfiguration do

  before do
    SpecHelper.init_i18n
    ASM::WsMan.stubs(:get_bios_enumeration).returns([])
  end

  describe 'when parsing NIC FQDDs' do

    # Blade examples:
    #
    # NIC.Integrated.1-1-1: 24:B6:FD:F9:FC:42
    # NIC.Integrated.1-1-2: 24:B6:FD:F9:FC:46
    # NIC.Integrated.1-1-3: 24:B6:FD:F9:FC:4A
    # NIC.Integrated.1-1-4: 24:B6:FD:F9:FC:4E
    # NIC.Integrated.1-2-1: 24:B6:FD:F9:FC:44
    # NIC.Integrated.1-2-2: 24:B6:FD:F9:FC:48
    # NIC.Integrated.1-2-3: 24:B6:FD:F9:FC:4C
    # NIC.Integrated.1-2-4: 24:B6:FD:F9:FC:50
    # NIC.Mezzanine.2B-1-1: 00:10:18:DC:C4:80
    # NIC.Mezzanine.2B-1-2: 00:10:18:DC:C4:84
    # NIC.Mezzanine.2B-1-3: 00:10:18:DC:C4:88
    # NIC.Mezzanine.2B-1-4: 00:10:18:DC:C4:8C
    # NIC.Mezzanine.2B-2-1: 00:10:18:DC:C4:82
    # NIC.Mezzanine.2B-2-2: 00:10:18:DC:C4:86
    # NIC.Mezzanine.2B-2-3: 00:10:18:DC:C4:8A
    # NIC.Mezzanine.2B-2-4: 00:10:18:DC:C4:8E
    #
    # Intel blade examples:
    #
    # NIC.Integrated.1-1-1: 24:B6:FD:F9:FC:42
    # NIC.Integrated.1-2-1: 24:B6:FD:F9:FC:44
    # NIC.Mezzanine.2B-1:   00:10:18:DC:C4:80
    # NIC.Mezzanine.2B-2:   00:10:18:DC:C4:82
    # NIC.Mezzanine.2C-1:   00:10:18:DC:C4:80
    # NIC.Mezzanine.2C-2:   00:10:18:DC:C4:82
    #
    # Rack examples:
    #
    # NIC.Slot.2-1-1: 00:0A:F7:06:88:50
    # NIC.Slot.2-1-2: 00:0A:F7:06:88:54
    # NIC.Slot.2-1-3: 00:0A:F7:06:88:58
    # NIC.Slot.2-1-4: 00:0A:F7:06:88:5C
    # NIC.Slot.2-2-1: 00:0A:F7:06:88:52
    # NIC.Slot.2-2-2: 00:0A:F7:06:88:56
    # NIC.Slot.2-2-3: 00:0A:F7:06:88:5A
    # NIC.Slot.2-2-4: 00:0A:F7:06:88:5E

    it 'should parse NIC.Embedded.1-1-1' do
      fqdd = ASM::NetworkConfiguration::NicView.new('NIC.Embedded.1-1-1')
      fqdd.type.should == 'Embedded'
      fqdd.card.should == '1'
      fqdd.fabric.should == 'A'
      fqdd.port.should == '1'
      fqdd.partition_no.should == '1'
    end

    it 'should parse NIC.Embedded.2-1-1' do
      fqdd = ASM::NetworkConfiguration::NicView.new('NIC.Embedded.2-1-1')
      fqdd.type.should == 'Embedded'
      fqdd.card.should == '1'
      fqdd.fabric.should == 'A'
      fqdd.port.should == '2'
      fqdd.partition_no.should == '1'
    end

    it 'should parse NIC.Integrated.1-1-1' do
      fqdd = ASM::NetworkConfiguration::NicView.new('NIC.Integrated.1-1-1')
      fqdd.type.should == 'Integrated'
      fqdd.card.should == '1'
      fqdd.fabric.should == 'A'
      fqdd.port.should == '1'
      fqdd.partition_no.should == '1'
    end

    it 'should parse NIC.Integrated.1-2-3' do
      fqdd = ASM::NetworkConfiguration::NicView.new('NIC.Integrated.1-2-3')
      fqdd.type.should == 'Integrated'
      fqdd.card.should == '1'
      fqdd.fabric.should == 'A'
      fqdd.port.should == '2'
      fqdd.partition_no.should == '3'
    end

    it 'should parse NIC.Mezzanine.2B-2-4' do
      fqdd = ASM::NetworkConfiguration::NicView.new('NIC.Mezzanine.2B-2-4')
      fqdd.type.should == 'Mezzanine'
      fqdd.card.should == '2'
      fqdd.fabric.should == 'B'
      fqdd.port.should == '2'
      fqdd.partition_no.should == '4'
    end

    it 'should be confused by NIC.Mezzanine.2C-2-4' do
      @logger = mock('NIC.Mezzanine.2C-2-4')
      @logger.expects(:warn)
      fqdd = ASM::NetworkConfiguration::NicView.new('NIC.Mezzanine.2C-2-4', @logger)
      fqdd.type.should == 'Mezzanine'
      fqdd.card.should == '2'
      fqdd.fabric.should == 'C'
      fqdd.port.should == '2'
      fqdd.partition_no.should == '4'
    end

    it 'should parse NIC.Mezzanine.2B-2' do
      fqdd = ASM::NetworkConfiguration::NicView.new('NIC.Mezzanine.2B-2')
      fqdd.type.should == 'Mezzanine'
      fqdd.card.should == '2'
      fqdd.fabric.should == 'B'
      fqdd.port.should == '2'
      fqdd.partition_no.should == '1'
    end

    it 'should parse rack fqdd in port 1' do
      fqdd = ASM::NetworkConfiguration::NicView.new('NIC.Slot.2-1-1')
      fqdd.type.should == 'Slot'
      fqdd.card.should == '2'
      # NOTE: these are rack fqdds, so maybe we should not populate fabric info...
      fqdd.fabric.should == 'B'
      fqdd.port.should == '1'
      fqdd.partition_no.should == '1'
    end

    it 'should parse rack fqdd in port 2' do
      fqdd = ASM::NetworkConfiguration::NicView.new('NIC.Slot.2-2-3')
      fqdd.type.should == 'Slot'
      fqdd.card.should == '2'
      # NOTE: these are rack fqdds, so maybe we should not populate fabric info...
      fqdd.fabric.should == 'B'
      fqdd.port.should == '2'
      fqdd.partition_no.should == '3'
    end

  end

  def build_nic_views(fqdd_to_mac, vendor = nil, product = nil)
    fqdd_to_mac.keys.map do |fqdd|
      mac = fqdd_to_mac[fqdd]
      nic_view = {"FQDD" => fqdd, "PermanentMACAddress" => mac, "CurrentMACAddress" => mac}
      unless block_given? && yield(nic_view)
        nic_view["LinkSpeed"] = "5"
        nic_view["VendorName"] = vendor if vendor
        nic_view["ProductName"] = product if product
      end
      nic_view
    end
  end

  describe 'when parsing a partitioned network config' do
    let (:json) { SpecHelper.load_fixture("network_configuration/blade_partitioned.json") }
    let (:net_config) { ASM::NetworkConfiguration.new(JSON.parse(json)) }

    it "should not include cards in to_hash" do
      # The cards array will contain complex types such as ASM::NicType that
      # will break puppet asm process_node yaml processing
      expect(net_config.to_hash.keys).not_to include("cards")
    end

    it "should not include ipRanges in networkObjects" do
      net_config.get_all_partitions.each do |partition|
        if partition.static
          expect(partition.staticNetworkConfiguration.ipRange).to be_nil
        end
      end
    end

    it 'should set interface, partition info on partitions' do
      net_config.add_partition_info!
      partition_index = 0
      card = net_config.cards.first
      # Verify first interface partitions set correctly
      (1..2).each do |port_no|
        port = card.interfaces.find { |p| p.name == "Port #{port_no}" }
        (1..4).each do |partition_no|
          fqdd = "NIC.Integrated.1-#{port_no}-#{partition_no}"
          partition = port.partitions.find { |p| p.name == partition_no.to_s }
          partition.port_no.should == port_no
          partition.partition_no.should == partition_no
          partition.partition_index.should == partition_index
          partition_index += 1
        end
      end
    end

    it 'should populate blade nic data' do
      fqdd_to_mac = {'NIC.Integrated.1-1-1' => '00:0E:1E:0D:8C:30',
                     'NIC.Integrated.1-1-2' => '00:0E:1E:0D:8C:32',
                     'NIC.Integrated.1-1-3' => '00:0E:1E:0D:8C:34',
                     'NIC.Integrated.1-1-4' => '00:0E:1E:0D:8C:36',
                     'NIC.Integrated.1-2-1' => '00:0E:1E:0D:8C:31',
                     'NIC.Integrated.1-2-2' => '00:0E:1E:0D:8C:33',
                     'NIC.Integrated.1-2-3' => '00:0E:1E:0D:8C:35',
                     'NIC.Integrated.1-2-4' => '00:0E:1E:0D:8C:37',
      }
      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac, "Broadcom", "57810"))
      net_config.add_nics!(Hashie::Mash.new(:host => '127.0.0.1'))
      card = net_config.cards.first

      # Verify first interface partitions set correctly
      (1..2).each do |port_no|
        port = card.interfaces.find { |p| p.name == "Port #{port_no}" }
        (1..4).each do |partition_no|
          fqdd = "NIC.Integrated.1-#{port_no}-#{partition_no}"
          partition = port.partitions.find { |p| p.name == partition_no.to_s }
          partition.fqdd.should == fqdd
          partition.mac_address.should == fqdd_to_mac[fqdd]
        end
      end
    end

    it 'should fail if interface not found' do
      ASM::WsMan.stubs(:get_nic_view).returns({})
      endpoint = Hashie::Mash.new
      endpoint.host = '127.0.0.1'
      expect do
        net_config.add_nics!(endpoint)
      end.to raise_error("Missing NICs for Interface (2x10Gb); none found")
    end

    it 'should fail if wrong NIC found' do
      fqdd_to_mac = {'NIC.Integrated.1-1-1' => '00:0E:1E:0D:8C:30',
                     'NIC.Integrated.1-2-1' => '00:0E:1E:0D:8C:31',
      }
      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac) do |nic_view|
        nic_view["LinkSpeed"] = "3" # 1 Gbps, not supported
      end)
      endpoint = Hashie::Mash.new
      endpoint.host = '127.0.0.1'
      expect do
        net_config.add_nics!(endpoint)
      end.to raise_error("Missing NICs for Interface (2x10Gb); available: NIC.Integrated.1 (2x1Gb)")
    end

    it 'should be able to generate missing partitions' do
      fqdd_to_mac = {'NIC.Integrated.1-1-1' => '00:0E:1E:0D:8C:30',
                     'NIC.Integrated.1-2-1' => '00:0E:1E:0D:8C:31',
      }
      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac, "Broadcom", "57810"))
      net_config.add_nics!(Hashie::Mash.new(:host => '127.0.0.1'), :add_partitions => true)
      card = net_config.cards.first

      # Verify all partitions set correctly
      (1..2).each do |port_no|
        port = card.interfaces.find { |p| p.name == "Port #{port_no}" }
        (1..4).each do |partition_no|
          fqdd = "NIC.Integrated.1-#{port_no}-#{partition_no}"
          partition = port.partitions.find { |p| p.name == partition_no.to_s }
          partition.fqdd.should == fqdd
          if partition_no == 1
            partition.mac_address.should == fqdd_to_mac[fqdd]
          else
            partition.mac_address.should be_nil
          end
        end
      end
    end

    it 'should find PXE networks' do
      partitions = net_config.get_partitions('PXE')
      partitions.size.should == 2
      partitions[0].name.should == '1'
      partitions[1].name.should == '1'
    end

    it 'should find multiple network types' do
      partitions = net_config.get_partitions('PUBLIC_LAN', 'PRIVATE_LAN')
      partitions.size.should == 2
      partitions[0].name.should == '3'
      partitions[1].name.should == '3'
    end

    it 'should find single networks' do
      networks = net_config.get_networks('HYPERVISOR_MANAGEMENT')
      networks.size.should == 1
      network = networks[0]
      network.name.should == 'Hypervisor Management'
      network.staticNetworkConfiguration.ipAddress.should == '172.28.113.50'
    end

    it 'should not find missing networks' do
      networks = net_config.get_networks('FILESHARE')
      networks.size.should == 0
    end

    it 'should find multiple networks' do
      networks = net_config.get_networks('PXE', 'HYPERVISOR_MANAGEMENT')
      networks.size.should == 2
    end

    it 'should find single network type' do
      network = net_config.get_network('HYPERVISOR_MANAGEMENT')
      network.name.should == 'Hypervisor Management'
      network.staticNetworkConfiguration.ipAddress.should == '172.28.113.50'
    end

    it 'should fail to find single network if multiple management networks found' do
      network_config = net_config
      orig = network_config.get_network('HYPERVISOR_MANAGEMENT')
      dup = Hashie::Mash.new(orig)
      dup.staticNetworkConfiguration.ipAddress = '172.28.12.119'
      network_config.cards[0].interfaces[0].partitions[2].networkObjects.push(dup)
      expect do
        network = network_config.get_network('HYPERVISOR_MANAGEMENT')
      end.to raise_error
    end

    it 'should fail to find single network if multiple management networks found' do
      expect do
        network = net_config.get_network('STORAGE_ISCSI_SAN')
      end.to raise_error
    end

    it 'should find storage networks with correct mac addresses' do
      fqdd_to_mac = {'NIC.Integrated.1-1-1' => '00:0E:1E:0D:8C:30',
                     'NIC.Integrated.1-1-2' => '00:0E:1E:0D:8C:32',
                     'NIC.Integrated.1-1-3' => '00:0E:1E:0D:8C:34',
                     'NIC.Integrated.1-1-4' => '00:0E:1E:0D:8C:36',
                     'NIC.Integrated.1-2-1' => '00:0E:1E:0D:8C:31',
                     'NIC.Integrated.1-2-2' => '00:0E:1E:0D:8C:33',
                     'NIC.Integrated.1-2-3' => '00:0E:1E:0D:8C:35',
                     'NIC.Integrated.1-2-4' => '00:0E:1E:0D:8C:37',
      }
      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac, "Broadcom", "57810"))
      net_config.add_nics!(Hashie::Mash.new(:host => '127.0.0.1'))
      partitions = net_config.get_partitions('STORAGE_ISCSI_SAN')
      partitions.size.should == 2
      partitions[0].name.should == '4'
      partitions[0].fqdd.should == 'NIC.Integrated.1-1-4'
      partitions[0].mac_address.should == '00:0E:1E:0D:8C:36'
      partitions[1].name.should == '4'
      partitions[1].fqdd.should == 'NIC.Integrated.1-2-4'
      partitions[1].mac_address.should == '00:0E:1E:0D:8C:37'
    end

    it 'should find single network ip addresses' do
      ips = net_config.get_static_ips('HYPERVISOR_MANAGEMENT')
      ips.should == ['172.28.113.50']
    end

    it 'should find multiple static ips of same type' do
      ips = net_config.get_static_ips('STORAGE_ISCSI_SAN')
      ips.sort.should == ['172.16.12.120', '172.16.12.121']
    end

    it 'should find multiple static ips with different types' do
      config = net_config
      ips = config.get_static_ips('HYPERVISOR_MANAGEMENT', 'STORAGE_ISCSI_SAN')
      ips.sort.should == ['172.16.12.120', '172.16.12.121', '172.28.113.50']
    end

    it 'should ignore dhcp when finding static ips' do
      ips = net_config.get_static_ips('PXE')
      ips.empty?.should == true
    end

  end

  describe 'when parsing an un-partitioned network config' do
    let (:json) { SpecHelper.load_fixture("network_configuration/blade_unpartitioned.json") }
    let (:net_config) { ASM::NetworkConfiguration.new(JSON.parse(json)) }

    it 'should only populate partition 1' do
      fqdd_to_mac = {'NIC.Integrated.1-1-1' => '00:0E:1E:0D:8C:30',
                     'NIC.Integrated.1-2-1' => '00:0E:1E:0D:8C:31',
                     'NIC.Mezzanine.2B-1-1' => '00:0F:1E:0D:8C:30',
                     'NIC.Mezzanine.2B-2-1' => '00:0F:1E:0D:8C:31',
                     'NIC.Mezzanine.3C-1-1' => '00:0D:1E:0D:8C:30',
                     'NIC.Mezzanine.3C-2-1' => '00:0D:1E:0D:8C:31',
      }
      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac))
      net_config.add_nics!(Hashie::Mash.new({:host => '127.0.0.1'}))

      card_index = 1
      card_name = "A"
      # Verify all partition 1 set correctly
      net_config.cards.each do |card|
        (1..2).each do |port_no|
          port = card.interfaces.find { |p| p.name == "Port #{port_no}" }
          partition = port.partitions.first
          #Only need to check partition 1, since other partitions aren't populated in cards if they aren't enabled
          fqdd = if card_index == 1
                   "NIC.Integrated.1-#{port_no}-1"
                 else
                   "NIC.Mezzanine.#{card_index}#{card_name}-#{port_no}-1"
                 end
          partition.fqdd.should == fqdd
          partition.mac_address.should == fqdd_to_mac[fqdd]
        end
        card_name = card_name.next
        card_index += 1
      end
    end

    it 'should work with Intel Mezz cards' do
      # Intel Mezz cards do not include the partition suffix in their FQDD
      fqdd_to_mac = {'NIC.Integrated.1-1-1' => '00:0E:1E:0D:8C:30',
                     'NIC.Integrated.1-2-1' => '00:0E:1E:0D:8C:31',
                     'NIC.Mezzanine.2B-1' => '00:0F:1E:0D:8C:30',
                     'NIC.Mezzanine.2B-2' => '00:0F:1E:0D:8C:31',
                     'NIC.Mezzanine.3C-1' => '00:0D:1E:0D:8C:30',
                     'NIC.Mezzanine.3C-2' => '00:0D:1E:0D:8C:31',
      }
      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac))
      net_config.add_nics!(Hashie::Mash.new({:host => '127.0.0.1'}))

      card_index = 1
      card_name = "A"
      # Verify all partition 1 set correctly
      net_config.cards.each do |card|
        (1..2).each do |port_no|
          port = card.interfaces.find { |p| p.name == "Port #{port_no}" }
          partition = port.partitions.first
          #Only need to check partition 1, since other partitions aren't populated in cards if they aren't enabled
          fqdd = if card_index == 1
                   "NIC.Integrated.1-#{port_no}-1"
                 else
                   "NIC.Mezzanine.#{card_index}#{card_name}-#{port_no}-1"
                 end
          partition.fqdd.should == fqdd
          partition.mac_address.should == fqdd_to_mac[fqdd]
        end
        card_name = card_name.next
        card_index += 1
      end
    end

  end

  describe 'when parsing a partitioned rack network config' do
    let (:json) { SpecHelper.load_fixture("network_configuration/rack_partitioned.json") }
    let (:net_config) { ASM::NetworkConfiguration.new(JSON.parse(json)) }

    it 'should match first card to first interface' do
      fqdd_to_mac = {'NIC.Slot.2-1-1' => '00:0A:F7:06:88:50',
                     'NIC.Slot.2-1-2' => '00:0A:F7:06:88:54',
                     'NIC.Slot.2-1-3' => '00:0A:F7:06:88:58',
                     'NIC.Slot.2-1-4' => '00:0A:F7:06:88:5C',
                     'NIC.Slot.2-2-1' => '00:0A:F7:06:88:52',
                     'NIC.Slot.2-2-2' => '00:0A:F7:06:88:56',
                     'NIC.Slot.2-2-3' => '00:0A:F7:06:88:5A',
                     'NIC.Slot.2-2-4' => '00:0A:F7:06:88:5E'}

      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac, "Broadcom", "57810"))
      net_config.add_nics!(Hashie::Mash.new({:host => '127.0.0.1'}))

      # Verify
      slot1 = net_config.interfaces[0]
      (1..2).each do |port_no|
        port = slot1.interfaces.find { |p| p.name == "Port #{port_no}" }
        (1..4).each do |partition_no|
          fqdd = "NIC.Slot.2-#{port_no}-#{partition_no}"
          partition = port.partitions.find { |p| p.name == partition_no.to_s }
          partition.fqdd.should == fqdd
          partition.mac_address.should == fqdd_to_mac[fqdd]
        end
      end
    end

    it 'should reset virtual mac addresses' do
      fqdd_to_mac = {'NIC.Integrated.1-1-1' => '00:0E:AA:6B:00:19',
                     'NIC.Integrated.1-1-2' => '00:0A:F7:06:88:54',
                     'NIC.Integrated.1-1-3' => '00:0A:F7:06:88:58',
                     'NIC.Integrated.1-1-4' => '00:0A:F7:06:88:5C',
                     'NIC.Integrated.1-2-1' => '00:0E:AA:6B:00:1E',
                     'NIC.Integrated.1-2-2' => '00:0A:F7:06:88:56',
                     'NIC.Integrated.1-2-3' => '00:0A:F7:06:88:5A',
                     'NIC.Integrated.1-2-4' => '00:0A:F7:06:88:5E'}

      nic_views = build_nic_views(fqdd_to_mac) do |nic_view|
        nic_view["ProductName"] = "unknown"
        nic_view["LinkSpeed"] = "5"
      end
      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac, "Broadcom", "57810"))
      net_config.add_nics!(Hashie::Mash.new({:host => '127.0.0.1'}))
      ASM::WsMan.unstub(:get_nic_view)

      raw_nic_views = SpecHelper.load_fixture("network_configuration/wsmanmacs.out")
      ASM::WsMan.stubs(:invoke).returns(raw_nic_views)
      net_config.reset_virt_mac_addr({:host => 'mock', :user => 'mocker', :password => 'mockest'})
      partitions = net_config.get_all_partitions
      partitions[0].lanMacAddress.should == '24:B6:FD:F4:4A:1E'
      partitions[0].iscsiMacAddress.should == '24:B6:FD:F4:4A:1E'
      partitions[4].lanMacAddress.should == '24:B6:FD:F4:4A:20'
      partitions[4].iscsiMacAddress.should == '24:B6:FD:F4:4A:20'
    end

  end

  describe 'when parsing a quad port rack network config' do
    let (:json) { SpecHelper.load_fixture("network_configuration/rack_quad_port.json") }
    let (:net_config) { ASM::NetworkConfiguration.new(JSON.parse(json)) }

    it 'should fail if quad port not available' do
      fqdd_to_mac = {'NIC.Slot.2-1-1' => '00:0A:F7:06:9D:C0',
                     'NIC.Slot.2-1-2' => '00:0A:F7:06:9D:C4',
                     'NIC.Slot.2-1-3' => '00:0A:F7:06:9D:C8',
                     'NIC.Slot.2-1-4' => '00:0A:F7:06:9D:CC',
                     'NIC.Slot.2-2-1' => '00:0A:F7:06:9D:C2',
                     'NIC.Slot.2-2-2' => '00:0A:F7:06:9D:C6',
                     'NIC.Slot.2-2-3' => '00:0A:F7:06:9D:CA',
                     'NIC.Slot.2-2-4' => '00:0A:F7:06:9D:CE', }

      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac))
      expect do
        net_config.add_nics!(Hashie::Mash.new({:host => '127.0.0.1'}), :add_partitions => true)
      end.to raise_error
    end

    it 'should configure if quad port available' do
      fqdd_to_mac = {'NIC.Integrated.1-1-1' => '00:0A:F7:06:9D:C0',
                     'NIC.Integrated.1-1-2' => '00:0A:F7:06:9D:C4',
                     'NIC.Integrated.1-2-1' => '00:0A:F7:06:9D:C8',
                     'NIC.Integrated.1-2-2' => '00:0A:F7:06:9D:CC',
                     'NIC.Integrated.1-3-1' => '00:0A:F7:06:9D:C2',
                     'NIC.Integrated.1-3-2' => '00:0A:F7:06:9D:C6',
                     'NIC.Integrated.1-4-1' => '00:0A:F7:06:9D:CA',
                     'NIC.Integrated.1-4-2' => '00:0A:F7:06:9D:CE', }

      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac, "Broadcom", "57840"))

      net_config.add_nics!(Hashie::Mash.new({:host => '127.0.0.1'}), :add_partitions => true)
      net_config.cards.size.should == 1
      # Verify
      card1 = net_config.cards.first
      (1..4).each do |port_no|
        port = card1.interfaces.find { |p| p.name == "Port #{port_no}" }
        (1..2).each do |partition_no|
          fqdd = "NIC.Integrated.1-#{port_no}-#{partition_no}"
          partition = port.partitions.find { |p| p.name == partition_no.to_s }
          partition.fqdd.should == fqdd
          partition.mac_address.should == fqdd_to_mac[fqdd]
        end
      end
    end

    it 'should configure if quad port available and not partitioned' do
      fqdd_to_mac = {'NIC.Integrated.1-1-1' => '00:0A:F7:06:9D:C0',
                     'NIC.Integrated.1-2-1' => '00:0A:F7:06:9D:C8',
                     'NIC.Integrated.1-3-1' => '00:0A:F7:06:9D:C2',
                     'NIC.Integrated.1-4-1' => '00:0A:F7:06:9D:CA', }

      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac, "Broadcom", "57840"))
      net_config = ASM::NetworkConfiguration.new(JSON.parse(json), :add_partitions)

      net_config.add_nics!(Hashie::Mash.new({:host => '127.0.0.1'}), :add_partitions => true)
      net_config.cards.size.should == 1
      # Verify
      card1 = net_config.cards.first
      (1..4).each do |port_no|
        port = card1.interfaces.find { |p| p.name == "Port #{port_no}" }
        (1..2).each do |partition_no|
          fqdd = "NIC.Integrated.1-#{port_no}-#{partition_no}"
          partition = port.partitions.find { |p| p.name == partition_no.to_s }
          partition.fqdd.should == fqdd
          if partition_no == 1
            partition.mac_address.should == fqdd_to_mac[fqdd]
          else
            partition.mac_address.should be_nil
          end
        end
      end
    end

  end

  describe 'when parsing an un-partitioned rack network config' do
    let (:json) { SpecHelper.load_fixture("network_configuration/rack_unpartitioned.json") }
    let (:net_config) { ASM::NetworkConfiguration.new(JSON.parse(json)) }

    it 'should match first cards to first interfaces' do
      fqdd_to_mac = {'NIC.Slot.5-1-1' => '00:0A:F7:06:88:50',
                     'NIC.Slot.5-1-2' => '00:0A:F7:06:88:54',
                     'NIC.Slot.5-1-3' => '00:0A:F7:06:88:58',
                     'NIC.Slot.5-1-4' => '00:0A:F7:06:88:5C',
                     'NIC.Slot.5-2-1' => '00:0A:F7:06:88:52',
                     'NIC.Slot.5-2-2' => '00:0A:F7:06:88:56',
                     'NIC.Slot.5-2-3' => '00:0A:F7:06:88:5A',
                     'NIC.Slot.5-2-4' => '00:0A:F7:06:88:5E',
                     'NIC.Slot.3-1-1' => '01:0A:F7:06:88:50',
                     'NIC.Slot.3-1-2' => '01:0A:F7:06:88:54',
                     'NIC.Slot.3-1-3' => '01:0A:F7:06:88:58',
                     'NIC.Slot.3-1-4' => '01:0A:F7:06:88:5C',
                     'NIC.Slot.3-2-1' => '01:0A:F7:06:88:52',
                     'NIC.Slot.3-2-2' => '01:0A:F7:06:88:56',
                     'NIC.Slot.3-2-3' => '01:0A:F7:06:88:5A',
                     'NIC.Slot.3-2-4' => '01:0A:F7:06:88:5E',
                     'NIC.Slot.1-1-1' => '02:0A:F7:06:88:50',
                     'NIC.Slot.1-1-2' => '02:0A:F7:06:88:54',
                     'NIC.Slot.1-1-3' => '02:0A:F7:06:88:58',
                     'NIC.Slot.1-1-4' => '02:0A:F7:06:88:5C',
                     'NIC.Slot.1-2-1' => '02:0A:F7:06:88:52',
                     'NIC.Slot.1-2-2' => '02:0A:F7:06:88:56',
                     'NIC.Slot.1-2-3' => '02:0A:F7:06:88:5A',
                     'NIC.Slot.1-2-4' => '02:0A:F7:06:88:5E',
                     'NIC.Slot.7-1-1' => '03:0A:F7:06:88:50',
                     'NIC.Slot.7-1-2' => '03:0A:F7:06:88:54',
                     'NIC.Slot.7-1-3' => '03:0A:F7:06:88:58',
                     'NIC.Slot.7-1-4' => '03:0A:F7:06:88:5C',
                     'NIC.Slot.7-2-1' => '03:0A:F7:06:88:52',
                     'NIC.Slot.7-2-2' => '03:0A:F7:06:88:56',
                     'NIC.Slot.7-2-3' => '03:0A:F7:06:88:5A',
                     'NIC.Slot.7-2-4' => '03:0A:F7:06:88:5E'}

      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac))
      net_config.add_nics!(Hashie::Mash.new({:host => '127.0.0.1'}))

      # Verify 3 cards, unpartitioned
      to_slots = {0 => 1, 1 => 3, 2 => 5, 3 => 7}
      found_macs = []
      (0..3).each do |card_index|
        card = net_config.cards.find { |c| c.card_index == card_index }
        slot = to_slots[card_index]
        (1..2).each do |port_no|
          port = card.interfaces.find { |p| p.name == "Port #{port_no}" }
          (1..4).each do |partition_no|
            fqdd = "NIC.Slot.#{slot}-#{port_no}-#{partition_no}"
            partition = port.partitions.find { |p| p.name == partition_no.to_s }
            if partition_no > 1
              partition.should be_nil
            else
              partition.fqdd.should == fqdd
              mac = fqdd_to_mac[fqdd]
              partition.mac_address.should == mac
              found_macs.include?(mac).should be(false)
              found_macs.push(mac)
            end
          end
        end
      end
    end

    it 'should prefer integrated to slot nics' do
      fqdd_to_mac = {'NIC.Slot.5-1-1' => '00:0A:F7:06:88:50',
                     'NIC.Slot.5-2-1' => '00:0A:F7:06:88:52',
                     'NIC.Slot.3-1-1' => '01:0A:F7:06:88:50',
                     'NIC.Slot.3-2-1' => '01:0A:F7:06:88:52',
                     'NIC.Slot.1-1-1' => '02:0A:F7:06:88:50',
                     'NIC.Slot.1-2-1' => '02:0A:F7:06:88:52',
                     'NIC.Slot.7-1-1' => '03:0A:F7:06:88:50',
                     'NIC.Slot.7-2-1' => '03:0A:F7:06:88:52',
                     'NIC.Integrated.1-1-1' => '04:0A:F7:06:88:50',
                     'NIC.Integrated.1-2-1' => '04:0A:F7:06:88:52',
      }

      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac))
      net_config.add_nics!(Hashie::Mash.new({:host => '127.0.0.1'}))

      # Verify 3 cards, unpartitioned
      to_fqdd = {0 => 'NIC.Integrated.1', 1 => 'NIC.Slot.1', 2 => 'NIC.Slot.3', }
      found_macs = []
      (0..2).each do |card_index|
        card = net_config.cards.find { |c| c.card_index == card_index }
        fqdd_prefix = to_fqdd[card_index]
        (1..2).each do |port_no|
          port = card.interfaces.find { |p| p.name == "Port #{port_no}" }
          (1..4).each do |partition_no|
            fqdd = "#{fqdd_prefix}-#{port_no}-#{partition_no}"
            partition = port.partitions.find { |p| p.name == partition_no.to_s }
            if partition_no > 1
              partition.should be_nil
            else
              partition.fqdd.should == fqdd
              mac = fqdd_to_mac[fqdd]
              partition.mac_address.should == mac
              found_macs.include?(mac).should be(false)
              found_macs.push(mac)
            end
          end
        end
      end
    end
  end

  describe 'when parsing an unpartitioned 2x10Gb,2x1Gb rack network config' do
    let (:json) { SpecHelper.load_fixture("network_configuration/rack_2x2_unpartitioned.json") }
    let (:net_config) { ASM::NetworkConfiguration.new(JSON.parse(json)) }

    it 'should match 2x10Gb,2x1Gb to integrated nic, remainder to slot nics' do
      fqdd_to_mac = {'NIC.Slot.5-1-1' => '00:0A:F7:06:88:50',
                     'NIC.Slot.5-2-1' => '00:0A:F7:06:88:52',
                     'NIC.Slot.3-1-1' => '01:0A:F7:06:88:50',
                     'NIC.Slot.3-2-1' => '01:0A:F7:06:88:52',
                     'NIC.Slot.1-1-1' => '02:0A:F7:06:88:50',
                     'NIC.Slot.1-2-1' => '02:0A:F7:06:88:52',
                     'NIC.Slot.7-1-1' => '03:0A:F7:06:88:50',
                     'NIC.Slot.7-2-1' => '03:0A:F7:06:88:52',
                     'NIC.Integrated.1-1-1' => '04:0A:F7:06:88:50',
                     'NIC.Integrated.1-2-1' => '04:0A:F7:06:88:52',
                     'NIC.Integrated.1-3-1' => '04:0A:F7:06:88:53',
                     'NIC.Integrated.1-4-1' => '04:0A:F7:06:88:54',
      }
      nic_views = build_nic_views(fqdd_to_mac) do |nic_view|
        if nic_view["FQDD"] =~ /Integrated/
          nic_view["VendorName"] = "Broadcom"
          nic_view["ProductName"] = "57800"
        end
      end

      ASM::WsMan.stubs(:get_nic_view).returns(nic_views)
      net_config.add_nics!(Hashie::Mash.new({:host => '127.0.0.1'}))

      # Verify 3 cards, unpartitioned
      to_fqdd = {0 => 'NIC.Integrated.1', 1 => 'NIC.Slot.1', 2 => 'NIC.Slot.3', }
      found_macs = []
      (0..2).each do |card_index|
        card = net_config.cards.find { |c| c.card_index == card_index }
        fqdd_prefix = to_fqdd[card_index]
        (1..2).each do |port_no|
          port = card.interfaces.find { |p| p.name == "Port #{port_no}" }
          (1..4).each do |partition_no|
            fqdd = "#{fqdd_prefix}-#{port_no}-#{partition_no}"
            partition = port.partitions.find { |p| p.name == partition_no.to_s }
            if partition_no > 1
              partition.should be_nil
            else
              partition.fqdd.should == fqdd
              mac = fqdd_to_mac[fqdd]
              partition.mac_address.should == mac
              found_macs.include?(mac).should be(false)
              found_macs.push(mac)
            end
          end
        end
      end
    end
  end

  describe 'when parsing a partitioned 2x10Gb,2x1Gb rack network config' do
    let (:json) { SpecHelper.load_fixture("network_configuration/rack_2x2_partitioned.json") }
    let (:net_config) { ASM::NetworkConfiguration.new(JSON.parse(json)) }

    it 'should match first card to first interface' do
      fqdd_to_mac = {'NIC.Slot.3-1-1' => '00:0C:F7:06:88:50',
                     'NIC.Slot.3-1-2' => '00:0C:F7:06:88:54',
                     'NIC.Slot.3-1-3' => '00:0C:F7:06:88:58',
                     'NIC.Slot.3-1-4' => '00:0C:F7:06:88:5C',
                     'NIC.Slot.3-2-1' => '00:0C:F7:06:88:52',
                     'NIC.Slot.3-2-2' => '00:0C:F7:06:88:56',
                     'NIC.Slot.3-2-3' => '00:0C:F7:06:88:5A',
                     'NIC.Slot.3-2-4' => '00:0C:F7:06:88:5E',
                     'NIC.Slot.2-1-1' => '00:0B:F7:06:88:50',
                     'NIC.Slot.2-1-2' => '00:0B:F7:06:88:54',
                     'NIC.Slot.2-1-3' => '00:0B:F7:06:88:58',
                     'NIC.Slot.2-1-4' => '00:0B:F7:06:88:5C',
                     'NIC.Slot.2-2-1' => '00:0B:F7:06:88:52',
                     'NIC.Slot.2-2-2' => '00:0B:F7:06:88:56',
                     'NIC.Slot.2-2-3' => '00:0B:F7:06:88:5A',
                     'NIC.Slot.2-2-4' => '00:0B:F7:06:88:5E',
                     'NIC.Integrated.1-1-1' => '00:0A:F7:06:88:50',
                     'NIC.Integrated.1-1-2' => '00:0A:F7:06:88:54',
                     'NIC.Integrated.1-2-1' => '00:0A:F7:06:88:52',
                     'NIC.Integrated.1-2-2' => '00:0A:F7:06:88:56',
                     'NIC.Integrated.1-3-1' => '00:0A:F8:06:88:56',
                     'NIC.Integrated.1-4-1' => '00:0A:F9:06:88:56', }

      nic_views = build_nic_views(fqdd_to_mac) do |nic_view|
        if nic_view["FQDD"] =~ /Integrated/
          nic_view["VendorName"] = "Broadcom"
          nic_view["ProductName"] = "57800"
        else
          nic_view["VendorName"] = "Broadcom"
          nic_view["ProductName"] = "57810"
        end
      end
      ASM::WsMan.stubs(:get_nic_view).returns(nic_views)
      net_config.add_nics!(Hashie::Mash.new({:host => '127.0.0.1'}))

      # Verify expected number of cards, interfacess and partitions
      expect(net_config.cards.size).to eq(3)
      (0..2).each do |card_i|
        expect(net_config.cards[card_i].interfaces.size).to eq(2)
      end
      (0..2).each do |interface_i|
        expect(net_config.cards[0].interfaces[0].partitions.size).to eq(2)
        expect(net_config.cards[1].interfaces[0].partitions.size).to eq(4)
        expect(net_config.cards[2].interfaces[0].partitions.size).to eq(4)
      end

      # Verify integrated nic partitions
      card_i = 0
      card = net_config.cards[card_i]
      (0..1).each do |port_i|
        (0..1).each do |partition_i|
          fqdd = "NIC.Integrated.1-%d-%d" % [port_i + 1, partition_i + 1]
          expect(card.interfaces[port_i].partitions[partition_i].fqdd).to eq(fqdd)
        end
      end

      # Verify slot nic partitions
      (1..2).each do |card_i|
        card = net_config.cards[card_i]
        (0..1).each do |port_i|
          (0..3).each do |partition_i|
            fqdd = "NIC.Slot.%d-%d-%d" % [card_i + 1, port_i + 1, partition_i + 1]
            expect(card.interfaces[port_i].partitions[partition_i].fqdd).to eq(fqdd)
          end
        end
      end
    end
  end

  describe 'when configuring nic team configuration' do
    let (:json) { SpecHelper.load_fixture("network_configuration/rack_partitioned.json") }
    let (:net_config) { ASM::NetworkConfiguration.new(JSON.parse(json)) }

    it "should raise error if add_nics! is not invoked" do
      expect {
        net_config.teams
      }.to raise_error("NIC MAC Address information needs to updated to network configuration. Invoke nc.add_nics!")
    end

    it "should return nic team configuration when add_nics! is already invoked" do
      fqdd_to_mac = {'NIC.Integrated.1-1-1' => '00:0A:F7:06:88:50',
                     'NIC.Integrated.1-1-2' => '00:0A:F7:06:88:54',
                     'NIC.Integrated.1-1-3' => '00:0A:F7:06:88:58',
                     'NIC.Integrated.1-1-4' => '00:0A:F7:06:88:5C',
                     'NIC.Integrated.1-2-1' => '00:0A:F7:06:88:52',
                     'NIC.Integrated.1-2-2' => '00:0A:F7:06:88:56',
                     'NIC.Integrated.1-2-3' => '00:0A:F7:06:88:5A',
                     'NIC.Integrated.1-2-4' => '00:0A:F7:06:88:5E'}

      ASM::WsMan.stubs(:get_nic_view).returns(build_nic_views(fqdd_to_mac, "Broadcom", "57810"))
      net_config.add_nics!(Hashie::Mash.new(:host => '127.0.0.1'))

      output = [{:networks=>[{"id"=>"ff80808146056aa20146057c08e503a1",
                              "name"=>"Hypervisor Management",
                              "description"=>nil,
                              "type"=>"HYPERVISOR_MANAGEMENT",
                              "vlanId"=>28, "static"=>true,
                              "staticNetworkConfiguration"=>
                                  {"gateway"=>"172.28.0.1",
                                   "subnet"=>"255.255.0.0",
                                   "primaryDns"=>"172.20.0.8",
                                   "secondaryDns"=>nil,
                                   "dnsSuffix"=>"aidev.net",
                                   "ipAddress"=>"172.28.12.116"}}],
                 :mac_addresses=>["00:0A:F7:06:88:50", "00:0A:F7:06:88:52"]},
                {:networks=>[{"id"=>"ff80808146056aa20146057c0a0b03b8",
                              "name"=>"vMotion",
                              "description"=>nil,
                              "type"=>"HYPERVISOR_MANAGEMENT",
                              "vlanId"=>23,
                              "static"=>false,
                              "staticNetworkConfiguration"=>nil}],
                 :mac_addresses=>["00:0A:F7:06:88:54", "00:0A:F7:06:88:56"]},
                {:networks=>[{"id"=>"ff80808146056aa20146057c0bf003d1",
                              "name"=>"Workload",
                              "description"=>nil,
                              "type"=>"PRIVATE_LAN",
                              "vlanId"=>27,
                              "static"=>false,
                              "staticNetworkConfiguration"=>nil}],
                 :mac_addresses=>["00:0A:F7:06:88:58", "00:0A:F7:06:88:5A"]},
                {:networks=>[{"id"=>"ff80808146056aa20146057c0aad03b9",
                              "name"=>"iSCSI",
                              "description"=>nil,
                              "type"=>"STORAGE_ISCSI_SAN",
                              "vlanId"=>16, "static"=>true,
                              "staticNetworkConfiguration"=>
                                  {"gateway"=>"172.16.0.1",
                                   "subnet"=>"255.255.0.0",
                                   "primaryDns"=>"172.20.0.8",
                                   "secondaryDns"=>nil,
                                   "dnsSuffix"=>"aidev.net",
                                   "ipAddress"=>"172.16.12.116"}}],
                 :mac_addresses=>["00:0A:F7:06:88:5C", "00:0A:F7:06:88:5E"]}]
      expect(net_config.teams).to eq(output)
    end

  end
end

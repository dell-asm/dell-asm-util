require 'spec_helper'
require 'asm/wsman'

describe ASM::WsMan do

  describe 'when parsing nicview with disabled 57800 and dual-port slot nic' do

    before do
      # NOTE: this data is from a rack with a dual-port slot nic and a quad-port
      # integrated nic. Note the quad-port nic isn't showing any current or
      # permanent mac addresses, so it isn't found in the get_mac_addresses call
      file_name = File.join(File.dirname(__FILE__), '..', '..',
                            'fixtures', 'wsman', 'nic_view.xml')
      @nic_view_response = File.read(file_name)
    end

    it 'should find current macs' do
      ASM::WsMan.stubs(:invoke).returns(@nic_view_response)
      macs = ASM::WsMan.get_mac_addresses(nil, nil)
      macs.should == {'NIC.Slot.2-1-1' => '00:0A:F7:06:9D:C0',
                      'NIC.Slot.2-1-2' => '00:0A:F7:06:9D:C4',
                      'NIC.Slot.2-1-3' => '00:0A:F7:06:9D:C8',
                      'NIC.Slot.2-1-4' => '00:0A:F7:06:9D:CC',
                      'NIC.Slot.2-2-1' => '00:0A:F7:06:9D:C2',
                      'NIC.Slot.2-2-2' => '00:0A:F7:06:9D:C6',
                      'NIC.Slot.2-2-3' => '00:0A:F7:06:9D:CA',
                      'NIC.Slot.2-2-4' => '00:0A:F7:06:9D:CE',
      }
    end

    it 'should find permanent macs' do
      ASM::WsMan.stubs(:invoke).returns(@nic_view_response)
      macs = ASM::WsMan.get_permanent_mac_addresses(nil, nil)
      macs.should == {'NIC.Slot.2-1-1' => '00:0A:F7:06:9D:C0',
                      'NIC.Slot.2-1-2' => '00:0A:F7:06:9D:C4',
                      'NIC.Slot.2-1-3' => '00:0A:F7:06:9D:C8',
                      'NIC.Slot.2-1-4' => '00:0A:F7:06:9D:CC',
                      'NIC.Slot.2-2-1' => '00:0A:F7:06:9D:C2',
                      'NIC.Slot.2-2-2' => '00:0A:F7:06:9D:C6',
                      'NIC.Slot.2-2-3' => '00:0A:F7:06:9D:CA',
                      'NIC.Slot.2-2-4' => '00:0A:F7:06:9D:CE',
      }
    end

  end

  describe 'when parsing nicview with enabled 5720 and dual-port slot nic' do

    before do
      # NOTE: this data is from a rack with a dual-port slot nic and a quad-port
      # integrated nic.
      file_name = File.join(File.dirname(__FILE__), '..', '..',
                            'fixtures', 'wsman', 'nic_view_57800.xml')
      @nic_view_response = File.read(file_name)
    end

    it 'should ignore Broadcom 5720 NICs' do
      # we don't have NicView output, so just make the 57810 look like a 5720
      @nic_view_response.gsub!(/(ProductName[>]Broadcom.*)BCM57800/, '\1BCM5720')
      ASM::WsMan.stubs(:invoke).returns(@nic_view_response)
      macs = ASM::WsMan.get_mac_addresses(nil, nil)
      macs.should == {'NIC.Slot.2-1-1' => '00:0A:F7:06:9E:20',
                      'NIC.Slot.2-1-2' => '00:0A:F7:06:9E:24',
                      'NIC.Slot.2-1-3' => '00:0A:F7:06:9E:28',
                      'NIC.Slot.2-1-4' => '00:0A:F7:06:9E:2C',
                      'NIC.Slot.2-2-1' => '00:0A:F7:06:9E:22',
                      'NIC.Slot.2-2-2' => '00:0A:F7:06:9E:26',
                      'NIC.Slot.2-2-3' => '00:0A:F7:06:9E:2A',
                      'NIC.Slot.2-2-4' => '00:0A:F7:06:9E:2E'}
    end
  end

end

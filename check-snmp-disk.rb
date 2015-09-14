#!/usr/bin/env ruby
# Check SNMP Disk
# ===
#
# This is a simple SNMP check disk script for Sensu,
# The tool get a mount point as a regex and search for it in the device description SNMP table
# and return the utilization status based on warning and critical thresholds
#
#
# Requires SNMP gem
#
# USAGE:
#
#   check-snmp -h host -C public -m /mnt -w 75 -c 85
#
#   if you want to search for specific device and not regex add a comma to the pattern:
#   check-snmp -h host -C public -m /, 
#
#  To search for device description in your server or applicance run the following command:
#  snmpwalk -v2c -c public host 1.3.6.1.2.1.25.2.3.1.3
#
#  Author Yossi Nachum   <nachum234@gmail.com>
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'
require 'snmp'

class CheckSNMP < Sensu::Plugin::Check::CLI
  option :host,
         short: '-h host',
         default: '127.0.0.1'

  option :community,
         short: '-C snmp community',
         default: 'public'

  option :mount_point,
         short: '-m mount point',
         default: '/'

  option :ignoremnt,
         short: '-i MNT[,MNT]',
         description: 'Ignore mount point(s)',
         proc: proc { |a| a.split(',') }

  option :warning,
         short: '-w warning',
         proc: proc(&:to_i),
         default: 80

  option :critical,
         short: '-c critical',
         proc: proc(&:to_i),
         default: 90

  option :snmp_version,
         short: '-v version',
         description: 'SNMP version to use (SNMPv1, SNMPv2c (default))',
         default: 'SNMPv2c'

  option :timeout,
         short: '-t timeout (seconds)',
         default: '1'
  
  def initialize
    super
    @crit_mnt = []
    @warn_mnt = []
  end

  def usage_summary
    (@crit_mnt + @warn_mnt).join(', ')
  end

  def run
    base_oid = '1.3.6.1.2.1.25.2.3.1'
    dev_desc_oid = base_oid + '.3'
    dev_unit_oid = base_oid + '.4'
    dev_size_oid = base_oid + '.5'
    dev_used_oid = base_oid + '.6'
    begin
      manager = SNMP::Manager.new(host: "#{config[:host]}",
                                  community: "#{config[:community]}",
                                  version: config[:snmp_version].to_sym,
                                  timeout: config[:timeout].to_i)
      response = manager.get_bulk(0, 200, [dev_desc_oid])
      dev_indexes = []
      response.each_varbind do |var|
        if var.value.to_s =~ /#{config[:mount_point]}/
          dev_indexes.push(var.name[-1])
        end
      end
      dev_indexes.each do |dev_index|
        response = manager.get(["#{dev_desc_oid}.#{dev_index}", "#{dev_unit_oid}.#{dev_index}", "#{dev_size_oid}.#{dev_index}", "#{dev_used_oid}.#{dev_index}"])
        dev_desc, dev_unit, dev_size, dev_used = response.varbind_list
        next if config[:ignoremnt] && config[:ignoremnt].include?(dev_desc.value.to_s.split(",")[0])
        perc = dev_used.value.to_f / dev_size.value.to_f * 100
        if perc > config[:critical]
          @crit_mnt << "#{dev_desc.value.to_s} = #{perc.round(2)}%"
        elsif perc > config[:warning]
          @warn_mnt << "#{dev_desc.value.to_s} = #{perc.round(2)}%"
        end
      end
    rescue SNMP::RequestTimeout
      unknown "#{config[:host]} not responding"
    rescue => e
      unknown "An unknown error occured: #{e.inspect}"
    end
    critical usage_summary unless @crit_mnt.empty?
    warning usage_summary unless @warn_mnt.empty?
    ok "All disk usage under #{config[:warning]}%"
    manager.close
  end
end

#! /usr/bin/env ruby
#
#   metrics-couchbase
#
# DESCRIPTION:
#   This plugin collect metrics from couchbase REST API.
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: rest-client
#   Gem: json
#
# USAGE:
#
# NOTES:
#   This plugin is tested against couchbase 2.5.x
#
# LICENSE:
#   Copyright 2015 Yossi Nachum. 
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/metric/cli'
require 'rest_client'
require 'json'

class CheckCouchbase < Sensu::Plugin::Metric::CLI::Graphite
  option :user,
         description: 'Couchbase Admin Rest API auth username',
         short: '-u USERNAME',
         long: '--user USERNAME'

  option :password,
         description: 'Couchbase Admin Rest API auth password',
         short: '-P PASSWORD',
         long: '--password PASSWORD'

  option :api,
         description: 'Couchbase Admin Rest API base URL',
         short: '-a URL',
         long: '--api URL',
         default: 'http://localhost:8091'

  option :hostname,
         description: 'Couchbase hostname server',
         long: '--hostname HOSTNAME',
         default: "#{Socket.gethostname}"

  option :scheme,
         description: 'Metric naming scheme, text to prepend to $queue_name.$metric',
         long: '--scheme SCHEME',
         default: "#{Socket.gethostname}.couchbase"

  def run
    timestamp = Time.now.to_i

    begin
      resource = '/pools/default'
      response = RestClient::Request.new(
        method: :get,
        url: "#{config[:api]}/#{resource}",
        user: config[:user],
        password: config[:password],
        headers: { accept: :json, content_type: :json }
      ).execute
      results = JSON.parse(response.to_str, symbolize_names: true)
    rescue Errno::ECONNREFUSED
      unknown 'Connection refused'
    rescue RestClient::ResourceNotFound
      unknown "Resource not found: #{resource}"
    rescue RestClient::RequestFailed
      unknown 'Request failed'
    rescue RestClient::RequestTimeout
      unknown 'Connection timed out'
    rescue RestClient::Unauthorized
      unknown 'Missing or incorrect Couchbase REST API credentials'
    rescue JSON::ParserError
      unknown 'couchbase REST API returned invalid JSON'
    end
    
    results[:nodes].each do |node|
      next unless node[:hostname].include? config[:hostname]

      node[:interestingStats].each do |k, v|
        output "#{config[:scheme]}.#{node[:hostname]}.#{k}", v, timestamp
      end
    end

    ok
  end
end

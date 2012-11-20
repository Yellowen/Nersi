# -----------------------------------------------------------------------------
# Nersi - project management software
# Copyright (C) 2012  Yellowen Inc
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA  02110-1301, USA.
# -----------------------------------------------------------------------------

require 'uri'
require 'cgi'


module Daarmaan
  
  # Rack middleware for daarmaan base authentication
  class AuthMiddleware
    
    def initialize app
      @app = app

      # Read the authentication configuration
      daarmaan_setup
    end 
    
    def call env

      session = env["rack.session"]
      if !session.has_key? :daarmaan
        # Setup the daarmaan object inside session object
        session[:daarmaan] = @daarmaan
      end

      request = Rack::Request.new(env)
      params = request.params
      uri = URI(request.url)

      if request.get?
        ticket = params["ticket"]
        ack = params["ack"]
        
        if ack
          # User not authenticated
          params.delete("ack")
          uri.query = URI.encode_www_form(params)
          session["answered"] = true
        end

        if ticket
          # user is authenticated in Daarmaan
          params.delete("ticket")
          uri.query = URI.encode_www_form(params)
        end

      else
        # Post request should be checked after logging user in or with
        # ticket and ack
      end

      status, headers, body = @app.call(env)
      
      response = Rack::Response.new(body, status,
                                    headers)
      
      if !session.has_key? "redirected"
        if session.has_key? "answered"
          url = uri.to_s
          if params.empty?
            url = url[0..-2]
          end
          response.redirect(url, 301)
          session["redirected"] = true
          session.delete("answered")
        else
          response.redirect(@daarmaan.login_url(uri.to_s), 301)
        end

      else
        session.delete("redirected")
      end

      response.finish
      return response.to_a
    end
    
    private

    # Read the authentication configuration    
    def daarmaan_setup
      if Rails.application.config.auth_config["method"] == "daarmaan"
        @daarmaan = Daarmaan::Server.new Rails.application.config.auth_config
      else
        @daarmaan = Daarmaan::Server.new 
      end
    end
    
  end


  # This class represent the Daarmaan authentication server
  class Server
    
    def initialize kwargs={}
      if !kwargs.empty?
        @host = kwargs["host"] or raise ArgumentError, "specify `host`"
        @host.chomp!("/")

        @service = kwargs["service_name"] or raise ArgumentError, "specify `service_name`"
        @key = kwargs["service_key"] or raise ArgumentError, "specify `service_key`"

        @login_url = kwargs.has_key?("login_url") ? kwargs["login_url"] : "/"
        @login_page = kwargs.has_key?("login_page") ? kwargs["login_page"] : "/"

        @initialized = true
      else
        @initialized = false
      end
    end


    def login_page next_url=nil
      params = "/?service=#{@service}"
      if next_url
        params = "#{params}&next=" + CGI.escape(next_url)
      end
      login_url = @login_page.chomp("/")
      "#{@host}#{login_url}#{params}"
    end

    def login_url next_url=nil
      params = "/?service=#{@service}"
      if next_url
        params = "#{params}&next=" + CGI.escape(next_url)
      end
      login_url = @login_url.chomp("/")
      "#{@host}#{login_url}#{params}"
    end

    def is_used?
      @initialized
    end

  end
end

=begin
 * selsync by Michael Witrant <mike @ lepton . fr>
 * Copyright (c) 2007 Michael Witrant.
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 * This program is distributed under the terms
 * of the GNU General Public License (read the COPYING file)
 * 
=end

require 'test/unit'
require 'dl/import'
require 'socket'
require 'timeout'

class SelSync
  module LIB
    extend DL::Importable
    dlload ".libs/libselsync.so"
    
    extern "struct selsync *selsync_init()"
    extern "int selsync_parse_arguments(struct selsync *, int, char **)"
    extern "void selsync_free(struct selsync *)"
    extern "int selsync_valid(struct selsync *)"
    extern "void selsync_start(struct selsync *)"
    extern "void selsync_process_next_event(struct selsync *)"
    extern "int selsync_owning_selection(struct selsync *)"
    extern "void selsync_disown_selection(struct selsync *)"
    
    module_function
    
  end

  def initialize
    @data = LIB.selsync_init
  end
  
  def [](name)
    @data[name]
  end
  
  def method_missing(name, *args, &block)
    fullname = "selsync_#{name}"
    if LIB.respond_to?(fullname)
      result = LIB.send(fullname, @data, *args, &block)
      @data.struct! 'IISIIISII', :check, :client, :hostname, :port, :socket, :server, :error, :widget, :selection
      result
    else
      raise "No method #{name} on #{inspect} nor #{fullname} on #{LIB.inspect}"
    end
  end
end

class TestSelSync < Test::Unit::TestCase
  def test_init
    selsync = SelSync.new
    assert selsync
    assert_equal 1, selsync.valid
    assert_equal 0, selsync[:client]
    assert_equal nil, selsync[:hostname]
    assert_equal 0, selsync[:port]
    assert_equal 0, selsync[:socket]
    assert_equal 0, selsync[:server]
    assert_not_equal 0, selsync[:widget]
    assert_not_equal 0, selsync[:selection]
  end
  
  def test_free
    selsync = SelSync.new
    selsync.free
    assert_equal 0, selsync.valid
  end
  
  def test_parse_client_arguments
    selsync = SelSync.new
    assert_equal 1, selsync.parse_arguments(3, ["./selsync", "bob", "4567"])
    assert_equal 1, selsync[:client]
    assert_equal "bob", selsync[:hostname].to_s
    assert_equal 4567, selsync[:port]
  end

  def test_parse_server_arguments
    selsync = SelSync.new
    assert_equal 1, selsync.parse_arguments(2, ["./selsync", "778"])
    assert_equal 0, selsync[:client]
    assert_equal nil, selsync[:hostname]
    assert_equal 778, selsync[:port]
  end
  
  def test_parse_wrong_arguments
    [
      ["./selsync"],
      ["foo", "bar", "baz", "bob"],
    ].each do |args|
      selsync = SelSync.new
      assert_equal 0, selsync.parse_arguments(args.size, args), args.inspect
    end
  end
  
  def test_client_connects
    %w( 127.0.0.1 localhost ).each do |hostname|
      server = TCPServer.new 4567
      selsync = SelSync.new
      selsync.parse_arguments(3, ["./selsync", hostname, "4567"])
      selsync.start
      assert_nothing_raised "connecting to #{hostname}" do
        timeout 1 do
          assert server.accept
        end
      end
      server.close
      assert_not_equal 0, selsync[:socket]
    end
  end
  
  def test_server_accepts_connection
    selsync = SelSync.new
    selsync.parse_arguments(2, ["./selsync", "8859"])
    selsync.start
    assert_not_equal 0, selsync[:server], selsync[:error].to_s
    
    assert_nothing_raised do
      timeout 1 do
        socket = TCPSocket.new "localhost", 8859
      end
    end
    assert_equal 0, selsync[:socket]
    selsync.process_next_event
    assert_not_equal 0, selsync[:socket]
    selsync.free
  end
  
  def test_server_reuse_port
    2.times do |i|
      selsync = SelSync.new
      selsync.parse_arguments(2, ["./selsync", "8857"])
      selsync.start
      assert_not_equal 0, selsync[:server], "pass #{i}: #{selsync[:error]}"
      selsync.free
    end
  end
  
  def test_client_owns_selection_on_start
    server = TCPServer.new 4568
    selsync = SelSync.new
    assert_equal 0, selsync.owning_selection
    selsync.parse_arguments(3, ["./selsync", "localhost", "4568"])
    selsync.start
    assert_equal 1, selsync.owning_selection
  end
  
  def test_client_lost_selection
    server = TCPServer.new 4567
    selsync = SelSync.new
    assert_equal 0, selsync.owning_selection
    selsync.parse_arguments(3, ["./selsync", "localhost", "4567"])
    selsync.start
    selsync.disown_selection
    assert_equal 0, selsync.owning_selection
    socket = server.accept
    assert_nothing_raised do
      timeout 1 do
        assert_equal 6, socket.read(1).unpack('c')[0]
        assert_equal 2, socket.read(1).unpack('c')[0]
      end
    end
  end
end

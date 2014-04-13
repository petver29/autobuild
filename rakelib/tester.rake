# Copyright (c) 2014 Maxim Trokhimtchouk
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'colorize'

class RegTest
	@@list = []
	attr_reader :name, :exe
	def RegTest.list
		@@list
	end
	def initialize(name, deps, basefiles, &block)
		@name = name
		@deps = deps
		@basefiles = basefiles.kind_of?(Array) ? basefiles : [basefiles]
		@code = block
		@@list.push(self)
	end
	def dependents
		@deps
	end
	def run builddir
		puts "TESTING: #{@name}".yellow
		@exe = builddir + '/' + @deps.sub(/\.exe$/,'')
		begin
			@code.call(self)
		rescue Exception => e
			puts "TEST #{@name} FAILED".red
			puts "#{e}"
		else
			puts "TEST #{@name} SUCCEDED".green
		ensure
			@exe = nil
		end
	end
	def assert_base
		@basefiles.each{|b|
			base = b.sub(/\.gz$/,'')
			test = base.sub(/\.base(\.?)/,'.test\1')
			bfiles = [base, base + '.gz'].select{|file| File.exists?(file)}
			tfiles = [test, test + '.gz'].select{|file| File.exists?(file)}
			raise "cannot find base file #{base}" if bfiles.empty?
			raise "cannot find test files #{test}" if tfiles.empty?
			files = [tfiles[0], bfiles[0]].map{|f|
				f =~ /\.gz$/ ? "<(gunzip -c #{f})" : f
			}
			result =  `zsh -c "diff #{files[0]} #{files[1]}"`
			raise "diff #{files[0]} #{files[1]}\n#{result}" unless $?.success?
		}
	end
end

def runcmd cmd
	sh cmd do |ok, res| raise "problems running #{cmd}" unless ok end
end

def regtest name, deps, basefiles, &block
	RegTest.new name, deps, basefiles, &block
end

def invoke_test mode
	proc do |t, args|
		(args.extras.empty? ? $tests : args.extras)
		.each{|t| require_relative "../" + t}
		deps = RegTest.list.collect{|t| t.dependents}.uniq
		Rake::Task[mode.to_sym()].invoke(*deps)
		builddir = build_dir(mode)
		RegTest.list.each{|t| t.run builddir}
	end
end

task :test_debug, &invoke_test('debug')
task :test_release, &invoke_test('release')

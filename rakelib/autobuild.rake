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

require 'set'

$OSNAME = `uname -s`.chomp
$OSVER = `uname -r`.chomp
$MACHINE = `uname -m`.chomp
$BUILDDIRROOT = "#{$OSNAME}#{$OSVER}-#{$MACHINE}"

$moddir = '.abuild'
$modes = ['release', 'debug']
$headerext = ['hpp', 'H']
$sourceext = ['cpp', 'C']
$srcincext = ['CXX', 'cxx']
$modext = $headerext + $sourceext + $srcincext

def build_dir mode
	raise "unknown mode #{mode}" unless $modes.include? mode
	$BUILDDIRROOT + '-' + mode
end

def split_top from
	head, _, tail = from.partition('/')
	raise "no top in #{from}" unless head && !head.empty? && tail && !tail.empty?
	return head, tail
end

def mode_from_build_dir name
	split_top(name).first[/-([^-]*)$/, 1]
end

def find_srcs_for_mod name, exts
	base = name.sub(/\.mod$/, '.')
	exts.map{|ext| base + ext}.select{|file| File.exists?(file)}
end

def read_mod name
	IO.readlines($moddir + '/' + name).map {|s| s.strip()}
end	

def all_dep_mods name, set
	if not set.include?(name)
		set.add(name)
		read_mod(name).each{|dep| all_dep_mods(dep, set)}
	end
	set
end

def get_objs_from_mod mods
	mods.select{|mod| !find_srcs_for_mod(mod, $sourceext).empty?()}
		.collect{|name| name.sub(/\.mod/, '.o')}
end

def dependencies src
	res = `gcc --std=c++11 -I. -Ivendor/include -MM #{src}`
	raise "could not resolve dependencies for #{src}" if $?.to_i != 0
	res.gsub("\\\n", '')[/^[^:]*:(.*)$/, 1].split(' ')
end

def make_mod name, srcs
	alldeps = srcs.collect{|src| dependencies(src)}.flatten - srcs
	gooddeps = alldeps.select{|src| $modext.include?(src[/\.(.*)$/, 1])}
	mods = gooddeps.map{|src| src.sub(/\.(.*)$/, '.mod')}.uniq
	modfile = $moddir + '/' + name
	mkpath File::dirname(modfile)
	open(modfile, "w") {|file| file.write(mods.join("\n"))}
end

def resolve_mod name
	srcs = find_srcs_for_mod name, $modext
	raise "cannot find any sources for #{name}" if srcs.empty?
	make_mod name, srcs unless uptodate?($moddir + '/' + name, srcs)
	read_mod name
end

def resolve_obj_dep name
	builddir, name = split_top name
	objmod = name.sub(/\.o$/, '.mod')
	find_srcs_for_mod(objmod, $modext) + 
	IO.readlines($moddir + '/' + objmod).map {|s| s.strip()}
		.collect{|src| find_srcs_for_mod src, $modext}.flatten
end

def resolve_exe_dep from
	builddir, name = split_top from
	mod = name.sub(/\.exe$/, '.mod')
	Rake::Task[mod].invoke()
	(get_objs_from_mod all_dep_mods(mod, Set.new()).to_a)
		.collect{|obj| builddir + '/' + obj}
end

def get_src obj
	mod = split_top(obj)[1].sub(/\.o$/, '.mod')
	src = find_srcs_for_mod mod, $sourceext
	raise "object #{obj} has more than one source #{src}" if src.length > 1
	raise "object #{obj} has no source" if src.length == 0
	src[0]
end

def get_exe exe 
	exe.sub(/\.exe$/,'')
end

def resolve_local_path what, where
	File.absolute_path(what)[/#{where}\/(.*)$/, 1] or 
		raise "path #{what} is not in #{where}"
end

def CXX obj, src, mode
	mkpath File::dirname(obj)
	sh "#{CC} #{CFLAGS} #{MODE_CFLAGS[mode]} -c #{src} -o #{obj}"
end

def LINK exe, objs
	mkpath File::dirname(exe)
	sh "#{CC} #{CFLAGS} #{objs.join(' ')} #{LDFLAGS} -o #{exe}"
end

def invoke_tasks mode, tasks
	raise "no executables defined in exes" unless tasks
	builddir = build_dir(mode)
	tasks.collect{|t| resolve_local_path t, pwd()}
	     .each{|t| Rake::Task[builddir + '/' + t].invoke()}	
end

invoke_block = proc do |t, args|
	invoke_tasks(t.name, args.extras.empty? ? $exes : args.extras)
end

# NOTE(maxim): we must denote exe file with an extension to use rule
rule '.exe' => [proc {|from| resolve_exe_dep from}] do |t|
	LINK get_exe(t.name), t.prerequisites unless
		uptodate?(get_exe(t.name), t.prerequisites)
end

rule '.mod' => [proc {|from| resolve_mod from}]

rule '.o' => [proc {|from| resolve_obj_dep from}] do |t|
	mode = mode_from_build_dir(t.name)
	CXX t.name, get_src(t.name), mode
end

task :release, &invoke_block
task :debug, &invoke_block
task :all => [:release, :debug]
task :clean do |t, args|
	modes = args.extras.empty? ? ['release', 'debug'] : args.extras
	modes.each{|t| sh "rm -rf #{build_dir(t)}"}
end
# specialised make for Ozmoo

require 'fileutils'

$is_windows = (ENV['OS'] == 'Windows_NT')

if $is_windows then
	# Paths on Windows
    $X64 = "C:\\ProgramsWoInstall\\WinVICE-3.1-x64\\x64.exe -autostart-warp" # -autostart-delay-random"
    $C1541 = "C:\\ProgramsWoInstall\\WinVICE-3.1-x64\\c1541.exe"
    $EXOMIZER = "C:\\ProgramsWoInstall\\Exomizer-3.0.1\\win32\\exomizer.exe"
    $ACME = "acme.exe"
else
	# Paths on Linux
    $X64 = "/usr/bin/x64 -autostart-delay-random"
    $C1541 = "/usr/bin/c1541"
    $EXOMIZER = "exomizer/src/exomizer"
    $ACME = "acme"
end

$PRINT_DISK_MAP = false # Set to true to print which blocks are allocated

# Typically only SMALLBLOCK should be enabled.
$GENERALFLAGS = [
	'SMALLBLOCK', # Use 512 byte blocks instead of 1024 bytes blocks for virtual memory.
#	'VICE_TRACE', # Send the last instructions executed to Vice, to aid in debugging
#	'TRACE', # Save a trace of the last instructions executed, to aid in debugging
#	'SWEDISH_CHARS',
]

# For a production build, none of these flags should be enabled.
$DEBUGFLAGS = [
#	'DEBUG', # This gives some debug capabilities, like informative error messages. It is automatically included if any other debug flags are used.
#	'VIEW_STACK_RECORDS',
#	'PRINTSPEED'
#	'BENCHMARK',
#	'TRACE_FLOPPY',
#	'TRACE_VM',
#	'PRINT_SWAPS',
#	'TRACE_FLOPPY_VERBOSE',
#	'TRACE_PRINT_ARRAYS',
#	'TRACE_PROP',
#	'TRACE_READTEXT',
#	'TRACE_SHOW_DICT_ENTRIES',
#	'TRACE_TOKENISE',
#	'TRACE_VM_PC',
]

$INTERLEAVE = 9 # (1-21)

$CACHE_PAGES = 4 # Should normally be 2-8. Use 4 unless you have a good reason not to. One page will be added automatically if it would otherwise be wasted due to vmem alignment issues.

MODE_P = 1
MODE_S1 = 2
MODE_S2 = 3
MODE_D2 = 4
MODE_D3 = 5

mode = MODE_S1

DISKNAME_BOOT = 128
DISKNAME_STORY = 129
DISKNAME_SAVE = 130
DISKNAME_DISK = 131

$BUILD_ID = Random.rand(0 .. 2**32-1)

$VMEM_BLOCKSIZE = $GENERALFLAGS.include?('SMALLBLOCK') ? 512 : 1024

$ZEROBYTE = 0.chr

$TEMPDIR = File.join(__dir__, 'temp')
Dir.mkdir($TEMPDIR) unless Dir.exist?($TEMPDIR)

$labels_file = File.join($TEMPDIR, 'acme_labels.txt')
$ozmoo_file = File.join($TEMPDIR, 'ozmoo')
$zip_file = File.join($TEMPDIR, 'ozmoo_zip')
$good_zip_file = File.join($TEMPDIR, 'ozmoo_zip_good')
$compmem_filename = File.join($TEMPDIR, 'compmem.tmp')

################################## create_d64.rb
# copies zmachine story data (*.z3, *.z5 etc.) to a Commodore 64 floppy (*.d64)

class D64_image
	def initialize(disk_title:, d64_filename:, is_boot_disk:, forty_tracks:)
		@disk_title = disk_title
		@d64_filename = d64_filename
		@is_boot_disk = is_boot_disk

		@tracks = forty_tracks ? 40 : 35 # 35 or 40 are useful options
#		puts "Tracks: #{@tracks}"
		@skip_blocks_on_18 = 2 # 1: Just skip BAM, 2: Skip BAM and 1 directory block, 19: Skip entire track
		@config_track = 19
		@skip_blocks_on_config_track = (@is_boot_disk ? 2 : 0)
		@free_blocks = 664 + 19 - @skip_blocks_on_18 + 17 * (@tracks - 35) - @skip_blocks_on_config_track
		puts "Free disk blocks at start: #{@free_blocks}"
		@d64_file = nil
		
		@config_track_map = []
		@contents = Array.new(@tracks > 35 ? 196608 : 174848, 0)
		@track_offset = [0,
			0,21,42,63,84,
			105,126,147,168,189,
			210,231,252,273,294,
			315,336,357,376,395,
			414,433,452,471,490,
			508,526,544,562,580,
			598,615,632,649,666,
			683,700,717,734,751,
			768]
			
		# BAM
		@track1800 = [
			# $16500 = 91392 = 357 (18,0)
			0x12,0x01, # track/sector
			0x41, # DOS version
			0x00, # unused
			# mark track 1-16, sector 1-16 as reserved for story files
			# <free sectors>,<0-7>,<8-15>,<16-?, remaining bits 0>
			0x15,0xff,0xff,0x1f, # 16504, track 01 (21 sectors)
			0x15,0xff,0xff,0x1f, # 16508, track 02
			0x15,0xff,0xff,0x1f, # 1650c, track 03
			0x15,0xff,0xff,0x1f, # 16510, track 04
			0x15,0xff,0xff,0x1f, # 16514, track 05
			0x15,0xff,0xff,0x1f, # 16518, track 06
			0x15,0xff,0xff,0x1f, # 1651c, track 07
			0x15,0xff,0xff,0x1f, # 16520, track 08
			0x15,0xff,0xff,0x1f, # 16524, track 09
			0x15,0xff,0xff,0x1f, # 16528, track 10
			0x15,0xff,0xff,0x1f, # 1652c, track 11
			0x15,0xff,0xff,0x1f, # 16530, track 12
			0x15,0xff,0xff,0x1f, # 16534, track 13
			0x15,0xff,0xff,0x1f, # 16538, track 14
			0x15,0xff,0xff,0x1f, # 1653c, track 15
			0x15,0xff,0xff,0x1f, # 16540, track 16
			0x15,0xff,0xff,0x1f, # 16544, track 17
			0x11,0xfc,0xff,0x07, # 16548, track 18 (19 sectors)
			0x13,0xff,0xff,0x07, # 1654c, track 19
			0x13,0xff,0xff,0x07, # 16550, track 20
			0x13,0xff,0xff,0x07, # 16554, track 21
			0x13,0xff,0xff,0x07, # 16558, track 22
			0x13,0xff,0xff,0x07, # 1655c, track 23
			0x13,0xff,0xff,0x07, # 16560, track 24
			0x12,0xff,0xff,0x03, # 16564, track 25 (18 sectors)
			0x12,0xff,0xff,0x03, # 16568, track 26
			0x12,0xff,0xff,0x03, # 1656c, track 27
			0x12,0xff,0xff,0x03, # 16570, track 28
			0x12,0xff,0xff,0x03, # 16574, track 29
			0x12,0xff,0xff,0x03, # 16578, track 30
			0x11,0xff,0xff,0x01, # 1657c, track 31 (17 sectors)
			0x11,0xff,0xff,0x01,0x11,0xff,0xff,0x01,
			0x11,0xff,0xff,0x01,0x11,0xff,0xff,0x01,
			0xa0,0xa0,0xa0,0xa0,0xa0,0xa0,0xa0,0xa0, # label (game name)
			0xa0,0xa0,0xa0,0xa0,0xa0,0xa0,0xa0,0xa0,
			0xa0,0xa0,0x30,0x30,0xa0,0x32,0x41,0xa0,
			0xa0,0xa0,0xa0,0x00,0x00,0x00,0x00,0x00,
			0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
			0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
			0x11,0xff,0xff,0x01,0x11,0xff,0xff,0x01,
			0x11,0xff,0xff,0x01,0x11,0xff,0xff,0x01,
			0x11,0xff,0xff,0x01,0x00,0x00,0x00,0x00,
			0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
			0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
			0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
			0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
			0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
		]

		# Create a disk image. Return number of free blocks, or -1 for failure.

		for track in 36 .. 40 do
			@track1800[0xc0 + 4 * (track - 36) .. 0xc0 + 4 * (track - 36) + 3] = (track > @tracks ? [0,0,0,0] : [0x11,0xff,0xff,0x01])
		end
		
		puts "Creating disk image..."

		# Set disk title
		c64_title = name_to_c64(disk_title)
		@track1800[0x90 .. 0x9f] = Array.new(0x10, 0xa0)
		[c64_title.length, 0x10].min.times do |charno|
			@track1800[0x90 + charno] = c64_title[charno].ord
		end
		

	end # initialize

	def free_blocks
		@free_blocks
	end
	
	def add_story_data(max_story_blocks:, add_at_end:)
	
		story_data_length = $story_file_data.length - $story_file_cursor
		num_sectors = [story_data_length / 256, max_story_blocks].min
		if @is_boot_disk then
			allocate_sector(@config_track, 0)
			allocate_sector(@config_track, 1)
		end

		first_story_track = 1
		first_story_track_max_sectors = get_track_length(first_story_track)
		temp_sectors = num_sectors
		if add_at_end then
			@tracks.downto(1) do |track|
				track_sectors = get_track_length(track) - get_reserved_sectors(track)
				if temp_sectors > track_sectors then
					temp_sectors -= track_sectors
				else
					first_story_track = track
					first_story_track_max_sectors = temp_sectors
					break
				end
			end
		end

		for track in 1 .. @tracks do
			print "#{track}:" if $PRINT_DISK_MAP
			if num_sectors > 0 then
				reserved_sectors = get_reserved_sectors(track)
				sector_count = get_track_length(track)
				if track < first_story_track then
					sector_count = reserved_sectors
				elsif track == first_story_track
					sector_count = first_story_track_max_sectors + reserved_sectors
				elsif sector_count - reserved_sectors > num_sectors
					sector_count = num_sectors + reserved_sectors
				end
				track_map = Array.new(sector_count, 0)
				reserved_sectors.times do |i|
					track_map[i] = 1
				end
				free_sectors_in_track = sector_count - reserved_sectors
				last_story_sector = sector_count - 1
	#	Find right sector.
	#		1. Start at 0
	#		2. Find next free sector
	#		3. Decrease blocks to go. If < 0, we are done
	#		4. Mark sector as used.
	#		5. Add interleave, go back to 2	
				sector = 0
				free_sectors_in_track.times do
					while track_map[sector] != 0
						sector = (sector + 1) % sector_count
					end
					track_map[sector] = 1
					allocate_sector(track, sector)
					add_story_block(track, sector)
					@free_blocks -= 1
					num_sectors -= 1
					sector = (sector + $INTERLEAVE) % sector_count
				end
			
				# for sector in 0 .. get_track_length(track) - 1 do
					# print " #{sector}" if $PRINT_DISK_MAP
					# if @is_boot_disk && track == @config_track && sector < 2 then
						# allocate_sector(track, sector)
					# elsif (track != 18 || sector >= @skip_blocks_on_18) &&
							# (!@is_boot_disk || track != @config_track || sector >= @skip_blocks_on_config_track) &&
							# num_sectors > 0 then
						# allocate_sector(track, sector)
						# add_story_block(track, sector)
						# last_story_sector = sector
						# @free_blocks -= 1
						# num_sectors -= 1
					# end
				# end
				@config_track_map.push(32 * reserved_sectors + last_story_sector - reserved_sectors + 1)
#				end
			else
				@config_track_map.push 0
			end # if num_sectors > 0
			puts if $PRINT_DISK_MAP
		end # for track
#		puts num_sectors.to_s
		add_1800()
		add_1801()

		@config_track_map = @config_track_map.reverse.drop_while{|i| i==0}.reverse # Drop trailing zero elements

		@free_blocks
	end

	def config_track_map
		@config_track_map
	end
	
	def set_config_data(data)
		if !@is_boot_disk then
			puts "ERROR: Tried to save config data on a non-boot disk."
			exit 0
		elsif !(data.is_a?(Array)) or data.length > 512 then
			puts "ERROR: Tried to save config data on a non-boot disk."
			exit 0
		end
		@contents[@track_offset[@config_track] * 256 .. @track_offset[@config_track] * 256 + data.length - 1] = data
		
	end
	
	def save
		begin
			d64_file = File.open(@d64_filename, "wb")
		rescue
			puts "ERROR: Can't open #{@d64_filename} for writing"
			exit 0
		end
		d64_file.write @contents.pack("C*")
		d64_file.close
	end

	private
	
	def allocate_sector(track, sector)
		print "*" if $PRINT_DISK_MAP
		index1 = 4 * track
		index2 = 4 * track + 1 + (sector / 8)
		if track > 35 then # Use SpeedDOS 40-track BAM layout
			index1 += 0x30
			index2 += 0x30
		end
		# adjust number of free sectors
		@track1800[index1] -= 1
		# allocate sector
		index3 = 255 - 2**(sector % 8)
		@track1800[index2] &= index3
	end

	def get_track_length(track)
		@track_offset[track + 1] - @track_offset[track]
	end

	def get_reserved_sectors(track)
		return 0 + 
			(track == 18 ? @skip_blocks_on_18 : 0) + 
			(track == @config_track ? @skip_blocks_on_config_track : 0)
	end
	
	def add_1800()
		@contents[@track_offset[18] * 256 .. @track_offset[18] * 256 + 255] = @track1800
	end

	def add_1801()
		@contents[@track_offset[18] * 256 + 256] = 0 
		@contents[@track_offset[18] * 256 + 257] = 0xff 
	end

	def add_story_block(track, sector)
		story_block_added = false
		if $story_file_data.length > $story_file_cursor + 1
			@contents[256 * (@track_offset[track] + sector) .. 256 * (@track_offset[track] + sector) + 255] =
				$story_file_data[$story_file_cursor .. $story_file_cursor + 255].unpack("C*")
			$story_file_cursor += 256
			story_block_added = true
		end
		story_block_added
	end
end # class D64_image

################################## END create_d64.rb

def name_to_c64(name)
	# Convert camel case and underscore to spaces. Remove "The" or "A" at beginning if the name gets too long.
	c64_name = name.dup
	camel_case = c64_name =~ /[a-z]/ and c64_name =~ /[A-Z]/ and c64_name !~ / |_/ 
	if camel_case then
		c64_name.gsub!(/([a-z])([A-Z])/,'\1 \2')
		c64_name.gsub!(/A([A-Z])/,'A \1')
	end
	c64_name.gsub!(/_+/," ")
	c64_name.gsub!(/^(the|a) (.*)$/i,'\2') if c64_name.length > 16 
	
	c64_name.length.times do |charno|
		code = c64_name[charno].ord
		code &= 0xdf if code >= 0x61 and code <= 0x7a
		c64_name[charno] = code.chr
	end
	c64_name
end

def build_interpreter()
	necessarysettings =  " --setpc #{$start_address} -DCACHE_PAGES=#{$CACHE_PAGES} -DSTACK_PAGES=#{$stack_pages} -D#{$ztype}=1"
	necessarysettings +=  " --cpu 6510 --format cbm"
	generalflags = $GENERALFLAGS.empty? ? '' : " -D#{$GENERALFLAGS.join('=1 -D')}=1"
	debugflags = $DEBUGFLAGS.empty? ? '' : " -D#{$DEBUGFLAGS.join('=1 -D')}=1"
	colourflags = $colour_replacement_clause
	unless $default_colours.empty? # or $zcode_version >= 5
		colourflags += " -DBGCOL=#{$default_colours[0]} -DFGCOL=#{$default_colours[1]}"
	end
	if $border_colour
		colourflags += " -DBORDERCOL=#{$border_colour}"
	end
	if $statusline_colour
		colourflags += " -DSTATCOL=#{$statusline_colour}"
	end
	fontflag = $font_filename ? ' -DCUSTOM_FONT=1' : ''
    compressionflags = ''

    cmd = "#{$ACME}#{necessarysettings}#{fontflag}#{colourflags}#{generalflags}#{debugflags}#{compressionflags} -l \"#{$labels_file}\" --outfile \"#{$ozmoo_file}\" ozmoo.asm"
	puts cmd
    ret = system(cmd)
    exit 0 unless ret
	read_labels($labels_file);
	puts "Interpreter size: #{$program_end_address - $start_address} bytes."
end

def read_labels(label_file_name)
	$storystart = 0
	File.open(label_file_name).each do |line|
		$storystart = $1.to_i(16) if line =~ /\tstory_start\t=\s*\$(\w{3,4})\b/;
		$program_end_address = $1.to_i(16) if line =~ /\tprogram_end\t=\s*\$(\w{3,4})\b/;
	end
end

def build_specific_boot_file(vmem_preload_blocks, vmem_contents)
	compmem_clause = (vmem_preload_blocks > 0) ? " \"#{$compmem_filename}\"@#{$storystart},0,#{[vmem_preload_blocks * $VMEM_BLOCKSIZE, 0x10000 - $storystart, File.size($compmem_filename)].min}" : ''

	font_clause = ""
	if $font_filename then
#		font_clause = " \"#{$font_filename}\"@$0800,2"
		font_clause = " \"#{$font_filename}\"@2048"
	end
#	exomizer_cmd = "#{$EXOMIZER} sfx basic -B -X \'LDA $D012 STA $D020 STA $D418\' ozmoo #{$compmem_filename},#{$storystart} -o ozmoo_zip"
#	exomizer_cmd = "#{$EXOMIZER} sfx #{$start_address} -B -M256 -C -x1 #{font_clause} \"#{$ozmoo_file}\"#{compmem_clause} -o \"#{$zip_file}\""
	exomizer_cmd = "#{$EXOMIZER} sfx #{$start_address} -B -M256 -C #{font_clause} \"#{$ozmoo_file}\"#{compmem_clause} -o \"#{$zip_file}\""

	puts exomizer_cmd
	system(exomizer_cmd)
#	puts "Building with #{vmem_preload_blocks} blocks gives file size #{File.size($zip_file)}."
	File.size($zip_file)
end

def save_good_boot_file()
	File.delete($good_zip_file) if File.exist?($good_zip_file)
	File.rename($zip_file, $good_zip_file)
end

def build_boot_file(vmem_preload_blocks, vmem_contents, free_blocks)
	if vmem_preload_blocks > 0 then
		begin
			compmem_filehandle = File.open($compmem_filename, "wb")
		rescue
			puts "ERROR: Can't open #{$compmem_filename} for writing"
			exit 0
		end
		compmem_filehandle.write(vmem_contents[0 .. vmem_preload_blocks * $VMEM_BLOCKSIZE - 1])
		compmem_filehandle.close
	end

	max_file_size = free_blocks * 254
	puts "Max file size is #{max_file_size} bytes."
	if build_specific_boot_file(vmem_preload_blocks, vmem_contents) <= max_file_size then
		save_good_boot_file()
		return vmem_preload_blocks
	end
	puts "##### Built loader/interpreter with #{vmem_preload_blocks} virtual memory blocks preloaded: Too big #####\n\n"
	max_ok_blocks = -1 # We we never find a number of blocks which work, -1 will be returned to signal failure.  
	
	done = false
	min_failed_blocks = vmem_preload_blocks
	actual_blocks = -1
	last_build = -2
	until done
		if min_failed_blocks - max_ok_blocks < 2
			actual_blocks = max_ok_blocks
			done = true
		elsif min_failed_blocks - $dynmem_blocks < 1
			actual_blocks = max_ok_blocks
			done = true
		else
			mid = (min_failed_blocks + [max_ok_blocks, $dynmem_blocks].max) / 2
#			puts "Trying #{mid} blocks..."
			size = build_specific_boot_file(mid, vmem_contents)
			last_build = mid
			if size > max_file_size then
				puts "##### Built loader/interpreter with #{mid} virtual memory blocks preloaded: Too big #####\n\n"
				min_failed_blocks = mid
			else
				save_good_boot_file()
				puts "##### Built loader/interpreter with #{mid} virtual memory blocks preloaded: OK      #####\n\n"
				max_ok_blocks = mid
#				max_ok_blocks = [mid + (1.25 * (max_file_size - size) / $VMEM_BLOCKSIZE).floor.to_i, min_failed_blocks - 1].min  
			end
		end
	end
#	build_specific_boot_file(actual_blocks, vmem_contents) unless last_build == actual_blocks
	puts "Picked #{actual_blocks} blocks." if max_ok_blocks >= 0
	actual_blocks
end

def add_boot_file(storyname, d64_filename)
	ret = FileUtils.cp("#{d64_filename}", "#{storyname}.d64")
	puts "#{$C1541} -attach \"#{storyname}.d64\" -write \"#{$good_zip_file}\" story"
	system("#{$C1541} -attach \"#{storyname}.d64\" -write \"#{$good_zip_file}\" story")
end

def play(filename)
	command = "#{$X64} #{filename}"
	puts command
    system(command)
end

def limit_vmem_data(vmem_data)
	if $vmem_size < vmem_data[2] * $VMEM_BLOCKSIZE
		vmem_data[2] = $vmem_size / $VMEM_BLOCKSIZE
	end
end

def build_P(storyname, d64_filename, config_data, vmem_data, vmem_contents, preload_max_vmem_blocks, extended_tracks)
	max_story_blocks = 0
	
	boot_disk = false
	
	if $VMEM
		puts "ERROR: Tried to use build mode -P with VMEM."
		exit 0
	end
	
	if $vmem_size < $story_size
		puts "#{$vmem_size} < #{$story_size}"
		puts "ERROR: The whole story doesn't fit in memory. Please try another build mode."
		exit 1
	end
	
	disk = D64_image.new(disk_title: storyname, d64_filename: d64_filename, is_boot_disk: boot_disk, forty_tracks: extended_tracks)

	disk.add_story_data(max_story_blocks: max_story_blocks, add_at_end: extended_tracks) # Has to be run to finalize the disk

	free_blocks = disk.free_blocks()
	puts "Free disk blocks after story data has been written: #{free_blocks}"

	# Build loader + terp + preloaded vmem blocks as a file
#	puts "build_boot_file(#{preload_max_vmem_blocks}, #{vmem_contents.length}, #{free_blocks})"
	build_boot_file(preload_max_vmem_blocks, vmem_contents, free_blocks)
	
	disk.save()
	
	# Add loader + terp + preloaded vmem blocks file to disk
	if add_boot_file(storyname, d64_filename) != true
		puts "ERROR: Failed to write loader/interpreter to disk."
		exit 1
	end

	puts "Successfully built game as #{storyname}.d64"
	$bootdiskname = storyname
	nil # Signal success
end

def build_S1(storyname, d64_filename, config_data, vmem_data, vmem_contents, preload_max_vmem_blocks, extended_tracks)
	max_story_blocks = 9999
	
	boot_disk = true

	unless $VMEM
		puts "ERROR: Tried to use build mode other than -P with VMEM disabled."
		exit 0
	end
	
	disk = D64_image.new(disk_title: storyname, d64_filename: d64_filename, is_boot_disk: boot_disk, forty_tracks: extended_tracks)

	disk.add_story_data(max_story_blocks: max_story_blocks, add_at_end: extended_tracks)
	if $story_file_cursor < $story_file_data.length
		puts "ERROR: The whole story doesn't fit on the disk. Please try another build mode."
		exit 1
	end
	free_blocks = disk.free_blocks()
	puts "Free disk blocks after story data has been written: #{free_blocks}"

	# Build loader + terp + preloaded vmem blocks as a file
#	puts "build_boot_file(#{preload_max_vmem_blocks}, #{vmem_contents.length}, #{free_blocks})"
	vmem_preload_blocks = build_boot_file(preload_max_vmem_blocks, vmem_contents, free_blocks)
	if vmem_preload_blocks < $dynmem_blocks
#		puts "#{vmem_preload_blocks} < #{$dynmem_blocks}"
		# #	Temporary: write config_data and save disk, for debugging purposes
		# disk.set_config_data(config_data)
		# disk.save()
		puts "ERROR: The story fits on the disk, but not the loader/interpreter. Please try another build mode."
		exit 1
	end
	vmem_data[2] = vmem_preload_blocks

	# Add config data about boot / story disk
	disk_info_size = 11 + disk.config_track_map.length
	last_block_plus_1 = 0
	disk.config_track_map.each{|i| last_block_plus_1 += (i & 0x1f)}
# Data for disk: bytes used, device# = 0 (auto), Last story data sector + 1 (word), tracks used for story data, name = "Boot / Story disk"
	config_data += [disk_info_size, 0, last_block_plus_1 / 256, last_block_plus_1 % 256, 
		disk.config_track_map.length] + disk.config_track_map
	config_data += [DISKNAME_BOOT, "/".ord, " ".ord, DISKNAME_STORY, DISKNAME_DISK, 0]  # Name: "Boot / Story disk"
	config_data[4] += disk_info_size
	
	config_data += vmem_data

	#	puts config_data
	disk.set_config_data(config_data)
	
	disk.save()
	
	# Add loader + terp + preloaded vmem blocks file to disk
	if add_boot_file(storyname, d64_filename) != true
		puts "ERROR: Failed to write loader/interpreter to disk."
		exit 1
	end

	puts "Successfully built game as #{storyname}.d64"
	$bootdiskname = storyname
	nil # Signal success
end

def build_S2(storyname, d64_filename_1, d64_filename_2, config_data, vmem_data, vmem_contents, preload_max_vmem_blocks, extended_tracks)

	unless $VMEM
		puts "ERROR: Tried to use build mode other than -P with VMEM disabled."
		exit 0
	end

	config_data[7] = 3 # 3 disks used in total
	outfile1name = "#{storyname}_boot"
	outfile2name = "#{storyname}_story"
	max_story_blocks = 9999
	disk1 = D64_image.new(disk_title: storyname, d64_filename: d64_filename_1, is_boot_disk: true, forty_tracks: false)
	disk2 = D64_image.new(disk_title: storyname, d64_filename: d64_filename_2, is_boot_disk: false, forty_tracks: extended_tracks)
	free_blocks = disk1.add_story_data(max_story_blocks: 0, add_at_end: false)
	free_blocks = disk2.add_story_data(max_story_blocks: max_story_blocks, add_at_end: false)
		puts "Free disk blocks after story data has been written: #{free_blocks}"
	if $story_file_cursor < $story_file_data.length
		puts "ERROR: The whole story doesn't fit on the disk. Please try another build mode."
		exit 1
	end

	# Build loader + terp + preloaded vmem blocks as a file
	vmem_preload_blocks = build_boot_file(preload_max_vmem_blocks, vmem_contents, 664)
	vmem_data[2] = vmem_preload_blocks
	
	# Add config data about boot disk
	disk_info_size = 8
# Data for disk: bytes used, device# = 0 (auto), Last story data sector + 1 (word), tracks used for story data, name = "Boot disk"
	config_data += [disk_info_size, 0, 0, 0, 0]
	config_data += [DISKNAME_BOOT, DISKNAME_DISK, 0]  # Name: "Boot disk"
	config_data[4] += disk_info_size
	
	# Add config data about story disk
	disk_info_size = 8 + disk2.config_track_map.length
	last_block_plus_1 = 0
	disk2.config_track_map.each{|i| last_block_plus_1 += (i & 0x1f)}
# Data for disk: bytes used, device# = 0 (auto), Last story data sector + 1 (word), tracks used for story data, name = "Story disk"
	config_data += [disk_info_size, 0, last_block_plus_1 / 256, last_block_plus_1 % 256, 
		disk2.config_track_map.length] + disk2.config_track_map
	config_data += [DISKNAME_STORY, DISKNAME_DISK, 0]  # Name: "Story disk"
	config_data[4] += disk_info_size
	
	config_data += vmem_data

	#	puts config_data
	disk1.set_config_data(config_data)
	disk1.save()
	disk2.save()
	
	# Add loader + terp + preloaded vmem blocks file to disk
	if add_boot_file(outfile1name, d64_filename_1) != true
		puts "ERROR: Failed to write loader/interpreter to disk."
		exit 1
	end
	File.delete(outfile2name) if File.exist?(outfile2name)
	File.rename(d64_filename_2, "./#{outfile2name}.d64")
	
	puts "Successfully built game as #{outfile1name}.d64 + #{outfile2name}.d64"
	$bootdiskname = outfile1name
	nil # Signal success
end

def build_D2(storyname, d64_filename_1, d64_filename_2, config_data, vmem_data, vmem_contents, preload_max_vmem_blocks, extended_tracks)

	unless $VMEM
		puts "ERROR: Tried to use build mode other than -P with VMEM disabled."
		exit 0
	end

	config_data[7] = 3 # 3 disks used in total
	outfile1name = "#{storyname}_boot_story_1"
	outfile2name = "#{storyname}_story_2"
	disk1 = D64_image.new(disk_title: storyname, d64_filename: d64_filename_1, is_boot_disk: true, forty_tracks: extended_tracks)
	disk2 = D64_image.new(disk_title: storyname, d64_filename: d64_filename_2, is_boot_disk: false, forty_tracks: extended_tracks)

	# Figure out how to put story blocks on the disks in optimal way.
	# Rule 1: Save 160 blocks for loader on boot disk, if possible. 
	# Rule 2: Spread story data as evenly as possible, so heads will move less.
	max_story_blocks = 9999
	total_raw_story_blocks = ($story_size - $story_file_cursor) / 256
	if disk1.free_blocks() - 160 >= total_raw_story_blocks / 2 and disk2.free_blocks >= disk1.free_blocks
		max_story_blocks = total_raw_story_blocks / 2
	elsif disk1.free_blocks() - 160 + disk2.free_blocks >= total_raw_story_blocks
		max_story_blocks = disk1.free_blocks() - 160
	else
		max_story_blocks = total_raw_story_blocks - disk2.free_blocks()
	end
	
	free_blocks_1 = disk1.add_story_data(max_story_blocks: max_story_blocks, add_at_end: extended_tracks)
	puts "Free disk blocks on disk #1 after story data has been written: #{free_blocks_1}"
	free_blocks_2 = disk2.add_story_data(max_story_blocks: 9999, add_at_end: false)
	puts "Free disk blocks on disk #2 after story data has been written: #{free_blocks_2}"
	if $story_file_cursor < $story_file_data.length
		puts "ERROR: The whole story doesn't fit on the disk. Please try another build mode."
		exit 1
	end

	# Build loader + terp + preloaded vmem blocks as a file
	vmem_preload_blocks = build_boot_file(preload_max_vmem_blocks, vmem_contents, free_blocks_1)
	vmem_data[2] = vmem_preload_blocks
	
	# Add config data about boot disk / story disk 1
	disk_info_size = 13 + disk1.config_track_map.length
#	last_block_plus_1 = $dynmem_blocks * $VMEM_BLOCKSIZE / 256
	last_block_plus_1 = 0
	disk1.config_track_map.each{|i| last_block_plus_1 += (i & 0x1f)}
# Data for disk: bytes used, device# = 0 (auto), Last story data sector + 1 (word), tracks used for story data, name
	config_data += [disk_info_size, 0, last_block_plus_1 / 256, last_block_plus_1 % 256, 
		disk1.config_track_map.length] + disk1.config_track_map
	config_data += [DISKNAME_BOOT, DISKNAME_DISK, "/".ord, " ".ord, DISKNAME_STORY, DISKNAME_DISK, "1".ord, 0]  # Name: "Boot disk / Story disk 1"
	config_data[4] += disk_info_size
	
	# Add config data about story disk 2
	disk_info_size = 9 + disk2.config_track_map.length
	disk2.config_track_map.each{|i| last_block_plus_1 += (i & 0x1f)}
# Data for disk: bytes used, device# = 0 (auto), Last story data sector + 1 (word), tracks used for story data, name
	config_data += [disk_info_size, 0, last_block_plus_1 / 256, last_block_plus_1 % 256, 
		disk2.config_track_map.length] + disk2.config_track_map
	config_data += [DISKNAME_STORY, DISKNAME_DISK, "2".ord, 0]  # Name: "Story disk 2"
	config_data[4] += disk_info_size
	
	config_data += vmem_data

	#	puts config_data
	disk1.set_config_data(config_data)
	disk1.save()
	disk2.save()
	
	# Add loader + terp + preloaded vmem blocks file to disk
	if add_boot_file(outfile1name, d64_filename_1) != true
		puts "ERROR: Failed to write loader/interpreter to disk."
		exit 1
	end
	File.delete(outfile2name) if File.exist?(outfile2name)
	File.rename(d64_filename_2, "./#{outfile2name}.d64")
	
	puts "Successfully built game as #{outfile1name}.d64 + #{outfile2name}.d64"
	$bootdiskname = outfile1name
	nil # Signal success
end

def build_D3(storyname, d64_filename_1, d64_filename_2, d64_filename_3, config_data, vmem_data, vmem_contents, preload_max_vmem_blocks, extended_tracks)

	unless $VMEM
		puts "ERROR: Tried to use build mode other than -P with VMEM disabled."
		exit 0
	end

	config_data[7] = 4 # 4 disks used in total
	outfile1name = "#{storyname}_boot"
	outfile2name = "#{storyname}_story_1"
	outfile3name = "#{storyname}_story_2"
	disk1 = D64_image.new(disk_title: storyname, d64_filename: d64_filename_1, is_boot_disk: true, forty_tracks: false)
	disk2 = D64_image.new(disk_title: storyname, d64_filename: d64_filename_2, is_boot_disk: false, forty_tracks: extended_tracks)
	disk3 = D64_image.new(disk_title: storyname, d64_filename: d64_filename_3, is_boot_disk: false, forty_tracks: extended_tracks)

	# Figure out how to put story blocks on the disks in optimal way.
	# Rule: Spread story data as evenly as possible, so heads will move less.
	total_raw_story_blocks = ($story_size - $story_file_cursor) / 256
	max_story_blocks = total_raw_story_blocks / 2
	
	free_blocks_1 = disk1.add_story_data(max_story_blocks: 0, add_at_end: false)
	puts "Free disk blocks on disk #1 after story data has been written: #{free_blocks_1}"
	free_blocks_2 = disk2.add_story_data(max_story_blocks: max_story_blocks, add_at_end: false)
	puts "Free disk blocks on disk #2 after story data has been written: #{free_blocks_2}"
	free_blocks_3 = disk3.add_story_data(max_story_blocks: 9999, add_at_end: false)
	puts "Free disk blocks on disk #3 after story data has been written: #{free_blocks_3}"
	if $story_file_cursor < $story_file_data.length
		puts "ERROR: The whole story doesn't fit on the disk. Please try another build mode."
		exit 1
	end

	# Build loader + terp + preloaded vmem blocks as a file
	vmem_preload_blocks = build_boot_file(preload_max_vmem_blocks, vmem_contents, 664)
	vmem_data[2] = vmem_preload_blocks
	
	# Add config data about boot disk
	disk_info_size = 8
# Data for disk: bytes used, device# = 0 (auto), Last story data sector + 1 (word), tracks used for story data, name = "Boot disk"
	config_data += [disk_info_size, 0, 0, 0, 0]
	config_data += [DISKNAME_BOOT, DISKNAME_DISK, 0]  # Name: "Boot disk"
	config_data[4] += disk_info_size

	last_block_plus_1 = 0
	
	# Add config data about story disk 1
	disk_info_size = 9 + disk2.config_track_map.length
	disk2.config_track_map.each{|i| last_block_plus_1 += (i & 0x1f)}
# Data for disk: bytes used, device# = 0 (auto), Last story data sector + 1 (word), tracks used for story data, name
	config_data += [disk_info_size, 0, last_block_plus_1 / 256, last_block_plus_1 % 256, 
		disk2.config_track_map.length] + disk2.config_track_map
	config_data += [DISKNAME_STORY, DISKNAME_DISK, "1".ord, 0]  # Name: "Story disk 1"
	config_data[4] += disk_info_size

	# Add config data about story disk 2
	disk_info_size = 9 + disk3.config_track_map.length
	disk3.config_track_map.each{|i| last_block_plus_1 += (i & 0x1f)}
# Data for disk: bytes used, device# = 0 (auto), Last story data sector + 1 (word), tracks used for story data, name
	config_data += [disk_info_size, 0, last_block_plus_1 / 256, last_block_plus_1 % 256, 
		disk3.config_track_map.length] + disk3.config_track_map
	config_data += [DISKNAME_STORY, DISKNAME_DISK, "2".ord, 0]  # Name: "Story disk 2"
	config_data[4] += disk_info_size
	
	config_data += vmem_data

	#	puts config_data
	disk1.set_config_data(config_data)
	disk1.save()
	disk2.save()
	disk3.save()
	
	# Add loader + terp + preloaded vmem blocks file to disk
	if add_boot_file(outfile1name, d64_filename_1) != true
		puts "ERROR: Failed to write loader/interpreter to disk."
		exit 1
	end
	File.delete(outfile2name) if File.exist?(outfile2name)
	File.rename(d64_filename_2, "./#{outfile2name}.d64")
	File.delete(outfile3name) if File.exist?(outfile3name)
	File.rename(d64_filename_3, "./#{outfile3name}.d64")
	
	puts "Successfully built game as #{outfile1name}.d64 + #{outfile2name}.d64 + #{outfile3name}.d64"
	$bootdiskname = outfile1name
	nil # Signal success
end


def print_usage_and_exit
	puts "Usage: make.rb [-S1|-S2|-D2|-D3|-P] [-p:[n]] [-c <preloadfile>] [-o] [-sp:[n]] [-s] [-x] [-r] "
	puts "      [-f <fontfile>] [-rc:[n]=[c],[n]=[c]...] [-dc:[n]:[n]] [-bc:[n]] [-sc:[n]] <storyfile>"
	puts "  -S1|-S2|-D2|-D3|-P: specify build mode. Defaults to S1. See docs for details."
	puts "  -p:[n]: preload a a maximum of n virtual memory blocks to make game faster at start"
	puts "  -c: read preload config from preloadfile, previously created with -o"
	puts "  -o: build interpreter in PREOPT (preload optimization) mode. See docs for details."
	puts "  -sp: Use the specified number of pages for stack (2-9, default is 4)."
	puts "  -s: start game in Vice if build succeeds"
	puts "  -x: Use extended tracks (40 instead of 35) on 1541 disk"
	puts "  -r: Use reduced amount of RAM (-$CFFF). Only with -P."
	puts "  -f: Embed the specified font with the game. See docs for details."
	puts "  -rc: Replace the specified Z-code colours with the specified C64 colours. See docs for details."
	puts "  -dc: Use the specified background and foreground colours. See docs for details."
	puts "  -bc: Use the specified border colour. 0=same as bg, 1=same as fg. See docs for details."
	puts "  -sc: Use the specified status line colour. Only valid for Z3 games. See docs for details."
	puts "  storyfile: path optional (e.g. infocom/zork1.z3)"
	exit 0
end

i = 0
reduced_ram = false
await_preloadfile = false
await_fontfile = false
preloadfile = nil
$font_filename = nil
auto_play = false
optimize = false
extended_tracks = false
preload_max_vmem_blocks = 2**16 / $VMEM_BLOCKSIZE
limit_preload_vmem_blocks = false
$start_address = 0x0801
$program_end_address = 0x10000
$colour_replacements = []
$default_colours = []
$statusline_colour = nil
$stack_pages = 4 # Should normally be 2-6. Use 4 unless you have a good reason not to.
$border_colour = 0

begin
	while i < ARGV.length
		if await_preloadfile then
			await_preloadfile = false
			preloadfile = ARGV[i]
		elsif await_fontfile then
			await_fontfile = false
			$font_filename = ARGV[i]
		elsif ARGV[i] =~ /^-x$/ then
			extended_tracks = true
		elsif ARGV[i] =~ /^-o$/ then
			optimize = true
		elsif ARGV[i] =~ /^-s$/ then
			auto_play = true
		elsif ARGV[i] =~ /^-r$/ then
			reduced_ram = true
		elsif ARGV[i] =~ /^-p:(\d+)$/ then
			preload_max_vmem_blocks = $1.to_i
			limit_preload_vmem_blocks = true
		elsif ARGV[i] =~ /^-P$/ then
			mode = MODE_P
		elsif ARGV[i] =~ /^-S1$/ then
			mode = MODE_S1
		elsif ARGV[i] =~ /^-S2$/ then
			mode = MODE_S2
		elsif ARGV[i] =~ /^-D2$/ then
			mode = MODE_D2
		elsif ARGV[i] =~ /^-D3$/ then
			mode = MODE_D3
		elsif ARGV[i] =~ /^-rc:((?:\d\d?=\d\d?)(?:,\d=\d\d?)*)$/ then
			$colour_replacements = $1.split(/,/)
		elsif ARGV[i] =~ /^-dc:([2-9]):([2-9])$/ then
			$default_colours = [$1.to_i,$2.to_i]
		elsif ARGV[i] =~ /^-bc:([0-9])$/ then
			$border_colour = $1.to_i
		elsif ARGV[i] =~ /^-sc:([2-9])$/ then
			$statusline_colour = $1.to_i
		elsif ARGV[i] =~ /^-sp:([2-9])$/ then
			$stack_pages = $1.to_i
		elsif ARGV[i] =~ /^-c$/ then
			await_preloadfile = true
		elsif ARGV[i] =~ /^-f$/ then
			await_fontfile = true
			$start_address = 0x1000
		elsif ARGV[i] =~ /^-/i then
			puts "Unknown option: " + ARGV[i]
			raise "error"
		else 
			$story_file = ARGV[i]
		end
		i = i + 1
	end
	if !$story_file
		print_usage_and_exit()
	end
rescue
	print_usage_and_exit()
end

$VMEM = (mode != MODE_P)

$GENERALFLAGS.push('VMEM') if $VMEM

$GENERALFLAGS.push('ALLRAM') unless reduced_ram

$ALLRAM = $GENERALFLAGS.include?('ALLRAM')

$colour_replacement_clause = ''
unless $colour_replacements.empty?
	$colour_replacements.each do |r|
		r =~ /^(\d\d?)=(\d\d?)$/
		zcode_colour = $1
		c64_colour = $2
		if zcode_colour !~ /^[2-9]$/
			puts "-rc requires a Z-code colour value (2-9) to the left of the = character."
			exit 0
		end
		if c64_colour !~ /^([0-9]|1[0-5])$/
			puts "-rc requires a C64 colour value (0-15) to the right of the = character."
			exit 0
		end
		$colour_replacement_clause += " -DCOL#{zcode_colour}=#{c64_colour}" unless $colour_replacement_clause.include? "-DCOL#{zcode_colour}=" 
	end
end

if reduced_ram and mode != MODE_P
	puts "Option -r can't be used with this build mode."
	exit 0
end

if optimize and mode == MODE_P
	puts "Option -o can't be used with this build mode."
	exit 0
end

if limit_preload_vmem_blocks and !$VMEM
	puts "Option -p can't be used with this build mode."
	exit 0
end

if extended_tracks and !$VMEM
	puts "Option -x can't be used with this build mode."
	exit 0
end

if optimize then
	if preloadfile then
		puts "-c (preload story data) can not be used with -o."
		exit 0
	end
	$DEBUGFLAGS.push('PREOPT')
end

$DEBUGFLAGS.push('DEBUG') unless $DEBUGFLAGS.empty? or $DEBUGFLAGS.include?('DEBUG')


print_usage_and_exit() if await_preloadfile

# Check for file specifying which blocks to preload
preload_data = nil
if preloadfile then
	preload_raw_data = File.read(preloadfile)
	vmem_type = "clock"
	if preload_raw_data =~ /\$\$\$#{vmem_type}\n(([0-9a-f]{4}:\n?)+)\$\$\$/i
		preload_data = $1.gsub(/\n/, '').gsub(/:$/,'').split(':')
		puts "#{preload_data.length} blocks found for initial caching."
	else
		puts "No preload config data found (for vmem type \"#{vmem_type}\")."
		exit 1
	end
end

# divide $story_file into path, filename, extension (if possible)
path = File.dirname($story_file)
extension = File.extname($story_file)
filename = File.basename($story_file)
storyname = File.basename($story_file, extension)
#puts "storyname: #{storyname}" 

begin
	puts "Reading file #{$story_file}..."
	$story_file_data = IO.binread($story_file)
	$story_file_data += $ZEROBYTE * (1024 - ($story_file_data.length % 1024))
rescue
	puts "ERROR: Can't open #{$story_file} for reading"
	exit 0
end

$zcode_version = $story_file_data[0].ord
$ztype = "Z#{$zcode_version}"

if $statusline_colour and $zcode_version > 3
	puts "Option -sc can only be used with z3 story files."
	exit 0
end	

# check header.high_mem_start (size of dynmem + statmem)
high_mem_start = $story_file_data[4 .. 5].unpack("n")[0]

# check header.static_mem_start (size of dynmem)
$static_mem_start = $story_file_data[14 .. 15].unpack("n")[0]

# get dynmem size (in vmem blocks)
$dynmem_blocks = ($static_mem_start.to_f / $VMEM_BLOCKSIZE).ceil
puts "Dynmem blocks: #{$dynmem_blocks}"
if $VMEM and preload_max_vmem_blocks and preload_max_vmem_blocks < $dynmem_blocks then
	puts "Max preload blocks adjusted to dynmem size, from #{preload_max_vmem_blocks} to #{$dynmem_blocks}."
	preload_max_vmem_blocks = $dynmem_blocks
end

$story_file_cursor = $dynmem_blocks * $VMEM_BLOCKSIZE

$story_size = $story_file_data.length

save_slots = [255, 664 / (($static_mem_start.to_f + 256 * $stack_pages + 20) / 254).ceil.to_i].min
#puts "Static mem start: #{$static_mem_start}"
#puts "Save blocks: #{(($static_mem_start.to_f + 256 * $stack_pages + 20) / 254).ceil.to_i}"
#puts "Save slots: #{save_slots}"

config_data = 
[$BUILD_ID].pack("I>").unpack("CCCC") + 
[
# 0, 0, 0, 0, # Game ID
12, # Number of bytes used for disk information, including this byte
$INTERLEAVE, 
save_slots, # Save slots, change later if wrong
2, # Number of disks, change later if wrong
# Data for save disk: 8 bytes used, device# = 0 (auto), Last story data sector + 1 = 0 (word), tracks used for story data, name = "Save disk"
8, 0, 0, 0, 0, DISKNAME_SAVE, DISKNAME_DISK, 0 
]

# Create config data for vmem
if preload_data then
	vmem_data = [
		3 + 2 * preload_data.length, # Size of vmem data
		preload_data.length, # Number of suggested blocks
		preload_data.length, # Number of preloaded blocks (May change later due to lack of space on disk)
		]
	lowbytes = []
	preload_data.each do |block|
		vmem_data.push(block[0 .. 1].to_i(16))
		lowbytes.push(block[2 .. 3].to_i(16))
	end
	vmem_data += lowbytes;
	if preload_max_vmem_blocks and preload_max_vmem_blocks > preload_data.length then
		puts "Max preload blocks adjusted to suggested preload blocks, from #{preload_max_vmem_blocks} to #{preload_data.length}."
		preload_max_vmem_blocks = preload_data.length
	end
else # No preload data available
#	$dynmem_blocks = $dynmem_size / $VMEM_BLOCKSIZE
	total_vmem_blocks = $story_size / $VMEM_BLOCKSIZE
	if $DEBUGFLAGS.include?('PREOPT') then
		all_vmem_blocks = $dynmem_blocks
	else
		all_vmem_blocks = [51 * 1024 / $VMEM_BLOCKSIZE, total_vmem_blocks].min()
	end
	vmem_data = [
		3 + 2 * all_vmem_blocks, # Size of vmem data
		all_vmem_blocks, # Number of suggested blocks
		all_vmem_blocks, # Number of preloaded blocks (May change later due to lack of space on disk)
		]
	lowbytes = []
	all_vmem_blocks.times do |i|
		vmem_data.push(i <= $dynmem_blocks ? 0xc0 : 0x80)
		lowbytes.push(i * $VMEM_BLOCKSIZE / 256)
	end
	vmem_data += lowbytes;
end

vmem_contents = ""
vmem_data[1].times do |i|
	start_address = (vmem_data[3 + i] & 0x07) * 256 * 256 + vmem_data[3 + vmem_data[1] + i] * 256
#	puts start_address
	vmem_contents += $story_file_data[start_address .. start_address + $VMEM_BLOCKSIZE - 1]
end

build_interpreter()

$vmem_size = ($ALLRAM ? 0x10000 : 0xd000) - $storystart

if $storystart + $dynmem_blocks * $VMEM_BLOCKSIZE > 0xd000 then
	puts "ERROR: Dynamic memory is too big (#{$dynmem_blocks * $VMEM_BLOCKSIZE} bytes), would pass $D000. Maximum dynmem size is #{0xd000 - $storystart} bytes." 
	exit 1
end

limit_vmem_data(vmem_data)

if $VMEM and preload_max_vmem_blocks and preload_max_vmem_blocks > vmem_data[2] then
	puts "Max preload blocks adjusted to total vmem size, from #{preload_max_vmem_blocks} to #{vmem_data[2]}."
	preload_max_vmem_blocks = vmem_data[2]
end

case mode
when MODE_P
	d64_filename = File.join($TEMPDIR, "temp1.d64")
	error = build_P(storyname, d64_filename, config_data.dup, vmem_data.dup, vmem_contents, preload_max_vmem_blocks, extended_tracks)
when MODE_S1
	d64_filename = File.join($TEMPDIR, "temp1.d64")
	error = build_S1(storyname, d64_filename, config_data.dup, vmem_data.dup, vmem_contents, preload_max_vmem_blocks, extended_tracks)
when MODE_S2
	d64_filename_1 = File.join($TEMPDIR, "temp1.d64")
	d64_filename_2 = File.join($TEMPDIR, "temp2.d64")
	error = build_S2(storyname, d64_filename_1, d64_filename_2, config_data.dup, vmem_data.dup, vmem_contents, preload_max_vmem_blocks, extended_tracks)
when MODE_D2
	d64_filename_1 = File.join($TEMPDIR, "temp1.d64")
	d64_filename_2 = File.join($TEMPDIR, "temp2.d64")
	error = build_D2(storyname, d64_filename_1, d64_filename_2, config_data.dup, vmem_data.dup, vmem_contents, preload_max_vmem_blocks, extended_tracks)
when MODE_D3
	d64_filename_1 = File.join($TEMPDIR, "temp1.d64")
	d64_filename_2 = File.join($TEMPDIR, "temp2.d64")
	d64_filename_3 = File.join($TEMPDIR, "temp3.d64")
	error = build_D3(storyname, d64_filename_1, d64_filename_2, d64_filename_3, 
		config_data.dup, vmem_data.dup, vmem_contents, preload_max_vmem_blocks, extended_tracks)
else
	puts "Unsupported build mode. Currently supported modes: S1, S2."
	exit 1
end

if !error and auto_play then 
	play("#{$bootdiskname}.d64")
end


exit 0



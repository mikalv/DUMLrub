require 'nokogiri'
require "openssl"
require "base64"
include Base64
require "net/ftp"
require 'zlib'
require 'archive/tar/minitar'
include Archive::Tar

# Drop upgrade package.
ftp = Net::FTP.new('192.168.42.2')
ftp.passive = true
ftp.login("BackDatAssUp","IsDaRealest!" )
puts "Logged into the FTPD"
begin
    puts "Snagging firmware backup files..."
    ftp.chdir("/upgrade/upgrade/backup/")
    puts "Listing files"
    filenames = ftp.nlst()
    p filenames
    FileUtils.mkdir_p("backup")
    filenames.each{|filename| 
        puts "Downloading file: #{filename} to memory"
        encodedfile = ftp.getbinaryfile(filename,nil) 
        cipher = OpenSSL::Cipher::AES128.new(:CBC)
        cipher.decrypt
        cipher.key = "\x74\x68\x69\x73\x2d\x61\x65\x73\x2d\x6b\x65\x79\x00\x00\x00\x00"
        cipher.iv  = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        decrypted_plain_text = cipher.update(encodedfile) + cipher.final

        # https://github.com/MAVProxyUser/DJI_ftpd_aes_unscramble/commit/93537fdec26435537399ea8595e0eee8725f5759 
        # undo the weird xor stuff that DJI does to try and beat us       

        puts "reversing odd DJI XOR bytes"
        bytes = decrypted_plain_text.bytes.to_a
        0.upto(9) do |i|
            bytes[i] ^= 0x30 + i 
        end
        10.upto(15) do |i|
            bytes[i] ^= 0x57 + i 
        end

        # https://github.com/MAVProxyUser/DJI_ftpd_aes_unscramble/commit/73a21718c32ee2be96fc64b9b5acf033c5626176
        # Ruby uses PKCS7 Padding by default, so there's no need to adjust this
        
        #puts bytes.pack('c*')
        puts "Writing file: backup/#{filename}"
        File.open("backup/#{filename}", "w+") { |file| file.write(bytes.pack('c*')) }

    }

# Seek in 480 bytes and look for XML header (then skip it)
# 000001e0: 3c3f 786d 6c20 7665 7273 696f 6e3d 2231  <?xml version="1
cfg = Dir.glob('backup/*.cfg.sig')[0]
config_sig = File.read("#{cfg}")
startxml = config_sig.index("<dji>")
config_sig = config_sig[startxml..-24]

firmwarepackage = Nokogiri::XML(config_sig)
firmwarepackage_version = firmwarepackage.xpath('/dji/device/firmware/release').first['version']
puts "Firmware version inside package confirmed as #{firmwarepackage_version}"

firmwarepackage.xpath('/dji/device/firmware/release/module').each {|node|
    puts "#{node.text()} #{node['md5']}"
}

# validate the MD5's of the downloaded module files before tarring them up.  

#    File.open('dji_system.bin', 'wb') { |tar| 
#        filenames.each{|filename|
#            puts "Adding #{filename} to tar dji_system.bin (tar file)" 
#            Minitar.pack(filename, tar) 
#            File.unlink(filename)
#        }
#    }


rescue Net::FTPPermError
    puts "Weird FTP problem... unable to put the firmware .bin file"
end
ftp.close




require 'socket'

serverAddr = "localhost"
serverPort = 4444

s = TCPSocket.open(serverAddr,serverPort)

puts s.gets


t = Thread.new do
	while line = s.gets
		puts line
		sleep 0.1
	end
end	
t.run	

while true
	line = readline

	if line =~ /^q\s*$/ then
		break
	end

	s.write(line)

	sleep 0.1
		
end

puts "bye"

s.close


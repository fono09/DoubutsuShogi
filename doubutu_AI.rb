require 'socket'

default_settings = {
	["c",1] => [1,2],
	["c",2] => [1,1],
	["e",1] => [1,3],
	["e",2] => [2,1],
	["g",1] => [2,3],
	["g",2] => [0,0],
	["l",1] => [1,3],
	["l",2] => [1,0]
}
p default_settings
exit

class Piece
	def initialize(type,player,pos_x,pos_y)
		if default_settings[[type,player]] != [pos_x,pos_y] then
			raise "サーバー改変疑惑"
		end
		@type = type
		@player = player
		@pos_x = pos_x
		@pos_y = pos_y
	end

	def mv

	end

end

serverAddr = "localhost"
serverPort = 4444

s = TCPSocket.open(serverAddr,serverPort)

puts s.gets
Thread.abort_on_exception = true

t = Thread.new do

	while line = s.gets
		p line

		if line =~ /, / then
			board=[]
			line.chomp.split(/, /).map{|piece| 
				piece.split(/ /) 
			}.each{|piece|
				i = piece[0][0].codepoints[0].to_i - 'A'.codepoints[0].to_i
				j = piece[0][1].to_i - 1
				unless board[i] then
					board[i] = []
				end
				board[i][j] = piece[1]
			}
			p board
		end
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


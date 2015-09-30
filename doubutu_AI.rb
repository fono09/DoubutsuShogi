require 'socket'



p default_settings
exit

class Piece
	INITIAL_POSITION = {
		["c",1] => [1,2],
		["c",2] => [1,1],
		["e",1] => [1,3],
		["e",2] => [2,1],
		["g",1] => [2,3],
		["g",2] => [0,0],
		["l",1] => [1,3],
		["l",2] => [1,0]
	}
	#初期位置に関して
	
	MOVE_DIRECTION = {
		"c" => [true,false,false,false,false,false,false,false],
		"e" => [false,true,false,true,false,true,false,true],
		"g" => [true,false,true,false,true,false,true,false],
		"l" => [true,true,true,true,true,true,true,true],
		"h" => [true,true,true,false,true,false,true,true]
	}
	#時計回りに進行方向

	def initialize(type,player,pos_x,pos_y)
		if INITIAL_POSITION[[type,player]] != [pos_x,pos_y] then
			raise "Piece#initialize failed"
		end
		@type = type
		@player = player
		@pos_x = pos_x
		@pos_y = pos_y
	end

	def mv(dst_x,dst_y)
		
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


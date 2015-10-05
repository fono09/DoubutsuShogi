require 'socket'
require 'matrix'



p default_settings
exit
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
	"c" => [false,true,false,
		false,false,false,
		false,false,false],
		"e" => [false,true,false,
			true,false,true,
			false,true,false],
			"g" => [true,false,true,
				false,false,false,
				true,false,true],
				"l" => [true,true,true,
					true,false,true,
					true,true,true],
					"h" => [true,true,true,
						true,false,true,
						false,true,false]
}
#時計回りに進行方向


class Board

end

class Piece

	def initialize(p,m)
		@player = p
		@mv_dir = m
	end

	def vec_2_idx(vx,vy)
		return 1-vy,vx+1
	end

	def movable?(x,y)
		idx = vec_2_idx(x,y)
		dir = @player==1 ? @mv_dir : @mv_dir.reverse
		return dir[idx[0]][idx[1]] 
	end

end

class Chicken < Piece
	def initialize(p)
		super(p,[false,true,false,
			false,false,false,
			false,false,false])
	end

	def promotion
		@mv_dir = [true,true,true,
			true,false,true,
			false,true,false]
	end
end

class Elephant < Piece
	def initialize(p)
		super(p,[true,false,true,
		      false,false,false,
		      true,false,true])
	end
end

class Giraf < Piece
	def initialize(p)
		super(p,[false,true,false,
		      true,false,true,
		      false,true,false])
	end
end

class Lion < Piece
	def initialize(p)
		super(p,[true,true,true,
		      true,false,true,
		      true,true,true])
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


require 'socket'

class Board

	INITIAL_BOARD = [["g2", "--", "--", "e1"], ["l2", "c2", "c1", "l1"], ["e2", "--", "--", "g1"]]

	DATA_LENGTH = 96
	PIECE_LENGTH = 4
	REC_NUM = DATA_LENGTH/PIECE_LENGTH

	PLAYER1 = 0b0000
	PLAYER2 = 0b1000
	
	B = 0b0001
	C = 0b0010
	E = 0b0011
	G = 0b0100
	L = 0b0101
	H = 0b0111
	
	def initialize
		@raw_data = to_b(INITIAL_BOARD)
	end

	def to_b(board)
		bit = 0b0
		board.each do |line|
			line.each do |piece|
				unless piece=="--" then
					bit += eval(piece[0].upcase)
					bit += eval("PLAYER"+piece[1])
				else
					bit += B
				end
				bit = bit << 4
			end
		end
		
		zero_fill =  DATA_LENGTH - bit.bit_length
		if zero_fill > 0
			bit = bit << zero_fill
		end
		#零埋め

		return bit
	end

	def move_check(board,turn)
		board = to_b(board)
		win = 0b1111

		from = []
		to = []
		REC_NUM.times.with_index do |i|
			puts @raw_data
			puts board

			if  ((win << i)&(@raw_data ^ board)) != 0b0 then
				if board & (win << i) == 0b1 then
					from.push(i)
				end

				if board & (win << i) != 0b1 then
					to.push(i)
				end
			end

			p from
			p to

		end

	end

end

serverAddr = "localhost"
serverPort = 4444

s = TCPSocket.open(serverAddr,serverPort)

puts s.gets
Thread.abort_on_exception = true

board = Board.new()
whoami = ''
t = Thread.new do

	while line = s.gets
		p line

		if line =~ /You are Player(\d)/ then
			whoami = $1
		end

		if line =~ /, / && line !~ /Sorry,/ then
			data=[]
			line.chomp.split(/, /).map{|piece| 
				piece.split(/ /) 
			}.each{|piece|
				i = piece[0][0].codepoints[0].to_i - 'A'.codepoints[0].to_i
				j = piece[0][1].to_i - 1
				unless data[i] then
					data[i] = []
				end
				data[i][j] = piece[1]
			}
			
			s.write('whoami')

			board.move_check(data,whoami)

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


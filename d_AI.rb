require 'socket'

class Board
	attr_accessor :bits, :my_turn

	# 0b 4 * 12 bits + 2 * 6 bits = 60 bits
	BOARD_AREA = 48
	CAPTURED_PIECE_AREA = 12

	CAPTURED_PIECE_PLAYER_AREA = 6

	PIECE_LENGTH = 4
	NUM_OF_CELL = BOARD_AREA/PIECE_LENGTH

	CAPTURED_PIECE_LENGTH = 2
	NUM_OF_CAPTURED_TYPES = 3

	CP_BITASK = 0b11
	P_BITMASK = 0b1111
	
	BOARD_HEIGHT = 4
	BORAD_WIDTH = 3

	PLAYER1 = 0b0000
	PLAYER2 = 0b1000

	P_P_BITMASK = 0b1000
	P_T_BITMASK = 0b0111

	B = 0b0000
	#blank(not in use)
	
	C = 0b0001
	E = 0b0010
	G = 0b0011
	L = 0b0100
	H = 0b0101

	def initialize
		@bits = to_b("A1 g2, B1 l2, C1 e2, A2 --, B2 c2, C2 --, A3 --, B3 c1, C3 --, A4 e1, B4 l1, C4 g1,")
		@my_turn = nil
		@turn = nil
	end

	def turn(turn)
		@turn = turn
		return @turn == my_turn ? true : false
	end

	def to_b(str)
		bits = 0b0
		str.chomp!
		str.split(/, /).each do |line|
			piece = line.split(/ /)
			/([A-E])([1-6])/ =~ piece[0]
			col = $1.codepoints[0].to_i - 'A'.codepoints[0].to_i
			row = $2.to_i - 1

			temp_bits = 0b0
			type = ''
			player = 0b0
			unless /--/ =~ piece[1] then
				/([a-z])([1-2])/ =~ piece[1]
				type = eval($1.upcase)
				player = eval("PLAYER#{$2.to_i}")
				temp_bits+=type
				temp_bits+=player
			end

			if col < BOARD_WIDTH then
				bits += temp_bits << (col*BOARD_HEIGHT+row)*PIECE_LENGTH+CAPTURED_PIECE_AREA
			else
				temp_bits = 0b0
				if G-type < 0 then
					raise "LION has been taken. Check the board."
				end
				temp_bits += 0b1 << (G-type)*CAPTURED_PIECE_LENGTH
				bits += temp_bits << (CAPTURED_PIECE_PLAYER_AREA*(player == PLAYER1 ? 1 : 0))
			end
		end

		return bits
	end

	def movable?(i,a,b,c,d,e,f,g,h)
		top = i%4!=3
		right = i/4 >= 1
		bottom = i%4!=0
		left = i/4 < 2

		arr0 = [a && top,b && top && right,c && right,b && right && bottom,e && bottom,f && bottom && left,g && left,h && left && top]
		
		arr1 = [i+1, i-BOARD_HEIGHT+1, i-BOARD_HEIGHT, i-BOARD_HEIGHT-1, i-1, i+BOARD_HEIGHT-1]
		arr1.zip(arr0).select! do |obj| obj[1] != nil end
		arr1.map! do |obj| obj[0] end

		return arr1
	end

	def next_legal_boards
		self_piece = eval("PLAYER#{@turn}")
		board = @bits
		next_board = []

		blank_cells = []
		NUM_OF_CELL.times do |i|
			if (board >> (CAPTURED_PIECE_AREA + i)) & P_BITMASK == 0 then
				blank_cells.push(i)
			end
		end

		shift_length = 0
		if self_piece == PLAYER1 then
			shift_length += CAPTURED_PIECE_AREA
		end

		NUM_OF_CAPTURED_TYPES.times do |i|
			if board & (CP_BITMASK << (shift_length + i*CAPTURED_PIECE_LENGTH))  > 0 then
				temp = board - (0b1 << (shift_length + i*CAPTURED_PIECE_LENGTH))
				type = 0

				case i
				when 0 then
					type = G
				when 1 then
					type = E
				when 2 then
					type = C
				end

				blank_cells.each do |j|
					next_board.push(temp + type + self_piece)
				end
			end
		end

		NUM_OF_CELL.times do |i|
			if (board >> (CAPTURED_PIECE_AREA + i*PIECE_LENGTH)) & P_BITMASK != 0 then
				case board >> (CAPTURED_PIECE_AREA + i*PIECE_LENGTH)) & P_T_BITMASK
				when C then
					movable?(i,true,false,false,false,false,false,false,false).each do
					end
				when E then
					movable?(i,false,true,false,true,false,true,false,true).each do
					end
				when G then
					movable?(i,true,false,true,false,true,false,true,false).each do
					end
				when L then
					movable?(i,true,true,true,true,true,true,true,true).each do
					end
				when H then
					movable?(i,true,true,true,false,true,false,true,true).each do
					end
				end
			end

		end

	end

	def mv_check(str)
		diff = @bits^to_b(str)
		return nil if diff == 0
		2.times do |i|
			NUM_OF_CAPTURED_TYPES.times do |j|
				if diff & CP_BITASK =~ 0 then
					take = [i,j]
					diff = diff >> CP_BITASK
				end
			end
		end

		NUM_OF_CELL.times do |i|
		end	

	end

end

serverAddr = "localhost"
serverPort = 4444

s = TCPSocket.open(serverAddr,serverPort)

puts s.gets

board = Board.new

Thread.abort_on_exception = true

turn_listener = Thread.new do
	begin
		while true do
			s.write("board\n")
			sleep 0.1
			s.write("turn\n")
			sleep 0.1
		end
	ensure
		board.mv
		turn_listener.run
	end
end
turn_listener.run

rx = Thread.new do
	while line = s.gets do
		if line =~ /--/ then
			board.mv_check(line)
		end
		
		if line =~ /You are Player(\d)/ then
			board.my_turn = $1.to_i
		end
		
		if line =~ /^Player(\d)/ then
			turn_listener.kill if board.turn($1.to_i)
		end

		sleep 0.1
	end

end
rx.run

s.write("whoami\n")

while true do
	line = readline

	if line =~ /^q\s*$/ then
		break
	end

	s.write(line)

	sleep 0.1
end

s.close

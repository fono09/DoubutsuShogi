require 'socket'

#スレッド内例外で落とす
Thread.abort_on_exception = true

######## 内部棋譜ビットマップ#######
# 0b 4 * 12 bits(盤面) + 2 * 6 bits(持ち駒) = 60 bits

BOARD_HEIGHT = 4
BOARD_WIDTH = 3

BOARD_AREA = 48
PIECE_LENGTH = 4
NUM_OF_CELL = 12
P_BITMASK = 0b1111
P_P_BITMASK = 0b1000
P_T_BITMASK = 0b0111

CPIECE_AREA = 12
CPIECE_PLAYER_AREA = 6
CPIECE_LENGTH = 2
NUM_OF_CPIECE_TYPES = 3
CPIECE_BITASK = 0b11

PLAYER1 = 0b0000
PLAYER2 = 0b1000
NUM_OF_PLAYER = 2

B = 0b0000
C = 0b0001
E = 0b0010
G = 0b0011
L = 0b0100
H = 0b0101

MOVE_MESH_LENGTH = 9
MOVE = {
	B => 0b000000000,
	C => 0b000100000,
	E => 0b101000101,
	G => 0b010101010,
	L => 0b111101111,
	H => 0b110101110
}
MOVE_IDX = {
	8 => -1*BOARD_HEIGHT-1,
	7 => -1*BOARD_HEIGHT,
	6 => -1*BOARD_HEIGHT+1,
	5 => 1,
	4 => 0,
	3 => -1,
	2 => BOARD_HEIGHT-1,
	1 => BOARD_HEIGHT,
	0 => BOARD_HEIGHT+1
}

#ビット列操作面倒だからいい具合にする
class Integer
	
	def slice(first,last)
		#"%b"% ~(0b1111 << 10) ..1000011111111..
		return self.to_s(2)[(-last-1)..(-first-1)].to_i(2)
	end

	def overwrite(first,last,value)
		
		temp = self - (self.to_s(2)[(-last-1)..(-first-1)].to_i(2) << first)
		temp += (value << first)
		return temp
	end

end


#ソケット通信対するラッパ
class Server

	attr_reader :board, :my_turn, :turn

	def initialize(addr,port)
		@socket = TCPSocket.open(addr,port)
		@board = nil
		@cpiece = {}
		@my_turn = nil
		@turn = nil
		@events = [
			["board\n",Proc.new{|line|
				if line =~ /--/ then
					@board = to_b(line)
					save_cpiece_position(line)
				end
			}],
			["whoami\n",Proc.new{|line|
				if line =~ /You are Player(\d)\.$/ then
					@my_turn = eval("PLAYER#{$1.to_i}")
				end

			}],
			["turn\n",Proc.new{|line|
				if line =~ /^Player(\d)$/ then
					@turn = eval("PLAYER#{$1.to_i}")
				end
			}]
		]

		@listener = Thread.new do
			while line = @socket.gets do
				@events.each do |obj|
					obj[1].call(line)
				end
				sleep 0.1
			end
		end
		@listener.run

		@speaker = Thread.new do 
			while true do
				@events.each do |obj|
					@socket.write(obj[0])
					sleep 0.1
				end
			end
		end
		@speaker.run
			
	end

	def save_cpiece_position(board)
		@cpiece = {}
		lines = board.split(/, /)
		if lines.length > 3 then
			lines.each.with_index do |line|
				piece = line.split(/ /)
				@cpiece[piece[0]] = piece[1]
			end
		end
	end
			
	def to_b(str)
		bits = 0b0
		str.chomp!
		str.split(/, /).each do |line|
			piece = line.split(/ /)
			/([A-E])([1-6])/ =~ piece[0]
			col = $1.codepoints[0].to_i - 'A'.codepoints[0].to_i
			row = $2.to_i-1

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
			
			if col < BOARD_WIDTH && row < BOARD_HEIGHT then
				bits += temp_bits << ((NUM_OF_CELL-col*BOARD_HEIGHT-row-1)*PIECE_LENGTH+CPIECE_AREA)
			else
				temp_bits = 0b0
				if G-type < 0 then
					raise "LION has been taken. Check the board."
				end
				temp_bits += 0b1 << ((G-type)*CPIECE_LENGTH)
				bits += temp_bits << (CPIECE_PLAYER_AREA*(player == PLAYER1 ? 1 : 0))
			end
		end

	
		return bits
	end

	def to_mv(board)
		diff = @board ^ board
		from = ''
		to = ''
		#持ち駒指し検出
		NUM_OF_PLAYER.times do |j|
			NUM_OF_CPIECE_TYPES.times do |i|
				if (CPIECE_BITMASK << CPIECE_LENGTH) & (diff >> CPIECE_PLAYER_AREA*j) > 0 then
					if (CPIECE_BITMASK << CPIECE_LENGTH) & (board >> CPIECE_PLAYER_AREA*j) > 0 then
						case i
						when 0 
							from = @cpiece["g#{j+1}"]
						when 1 
							from = @cpiece["e#{j+1}"]
						when 2
							from = @cpiece["c#{j+1}"]
						end
						
					end
				end
			end
		end

		#ボード動かし検出
		NUM_OF_CELL.times do |i|
			if P_BITMASK & (diff >> (i*PIECE_LENGTH+CPIECE_AREA)) > 0 then
				if P_BITMASK & (board >> (i*PIECE_LENGTH+CPIECE_AREA)) == 0 then
					from = (i/4+'A'.codepoints[0]).pack('U') + (i%4+1).to_s
				elsif P_BITMASK & (@borad >> (i*PIECE_LENGTH+CPIECE_AREA)) == 0
					to = (i/4+'A'.codepoints[0]).pack('U') + (i%4+1).to_s
				else
					to = (i/4+'A'.codepoints[0]).pack('U') + (i%4+1).to_s
				end
			end
		end

		@socket.write("mv #{from} #{to}\n")
	end
			

	def debug_print
		puts "board %b\n" % @board
		puts "turn %b\n" % @turn
		puts "my_turn %b\n" % @my_turn
	end

	def wait
		while @board == nil || @turn == nil || @my_turn == nil do
			sleep 1
		end
	end
			
end

#ボードビット列に対する操作
class Board
	
	attr_reader :bits, :next_boards 
		#:rotated,

	def initialize(bits)
		@bits = bits
		#@rotated = [0,0]
		@next_boards = []
	end

	def is_board?(i)
		return (i < NUM_OF_CELL)
	end

	def get_piece(i)
		raise "Can't get CPIECE_AREA" unless is_board?(i)
		first = (NUM_OF_CELL-i-1)*PIECE_LENGTH+CPIECE_AREA
		last = first+CPIECE_LENGTH+1
		return @bits.slice(first,last)
	end

	def get_piece_player(i)
		return (get_piece(i)&P_P_BITMASK)
	end

	def get_piece_type(i)
		return (get_piece(i)&P_T_BITMASK)
	end

	def overwrite_piece(i,piece)
		raise "Can't overwrite CPIECE_AREA" unless is_board?(i)
		@bits = @bits.overwrite(i*PIECE_LENGTH+CPIECE_AREA,PIECE_LENGTH,piece)
	end

	def replace_piece(i,j)
		raise "Can't replace CPIECE_AREA"  unless is_board?(i) && is_board?(j)
		temp = get_piece(i)
		@bits = overwrite_piece(i,get_piece(j))
		@bits = overwrite_piece(j,temp)
	end

	def get_cpiece(i)
		raise "Can't get PIECE_AREA" if is_board?(i)
		first = (i-NUM_OF_CELL)
	end

	def capture_piece(i)
		raise "Can't capture CPIECE_AREA" unless is_board?(i)

		player = (get_piece_player(i) == PLAYER1 ? 0 : 1)
		#取った逆のプレイヤーの持ち駒が増える
		
		pos = nil
		case get_piece_type(i)
		when C
			pos = 2
		when E
			pos = 1
		when G
			pos = 0
		end

		if pos !=nil then
			temp = @bits.slice(CPIECE_PLAYER_AREA*player+CPIECE_LENGTH*pos,CPIECE_PLAYER_AREA*player+CPIECE_LENGTH*pos)
		overwrite_piece(i,0)
		
			@bits = @bits.overwrite(CPIECE_PLAYER_AREA*player+CPIECE_LENGTH*pos,CPIECE_LENGTH,temp+1)
		else
			puts "Lion #{i} Captured!!!"
		end

	end

	ROTATE_AXIS_P = 0
	ROTATE_AXIS_Y = 1
	def rotate(axis)
		case axis
		when ROTATE_AXIS_P
			(NUM_OF_CELL/2).times do |i|
				replace_piece(i,NUM_OF_CELL-i-1)
			end

			NUM_OF_CELL.times do |i|
				temp = get_piece(i)
				temp = temp[3]==0b0 ? temp.overwrite(3,1,0b1) : temp.overwrite(3,1,0b0)
				overwrite_piece(i,temp)
			end

			@rotated[0] = @rotated[0]==1 ? 0 : 1

		when ROTATE_AXIS_Y
			#DBに入れるとか大規模探索時に必要なやつ
			#Y軸回転して容量削減(回転基準未定義)
		end

	end

	def enum_next_board(player)
		@next_boards.clear
		NUM_OF_CELL.times do |i|
			
			next unless get_piece_player(i) == player
			
			puts "get_piece_type(i):#{"%b" % get_piece_type(i)}"
			puts "MOVE[get_piece_type(i)]:#{"%b" % MOVE[get_piece_type(i)]}"
			mesh = MOVE[get_piece_type(i)]
			
			puts "mesh:%b"%mesh
			next if mesh == 0
			#空だったら次
			
			MOVE_MESH_LENGTH.times do |j|
				j = MOVE_MESH_LENGTH - j - 1 if player == PLAYER1
				#PLAYER1基準で舐めるとLSBからになる 逆は自然にできる

				next if mesh[j].zero?
				#空だったら

				next if 6 < j && i/BOARD_HEIGHT < 1 
				next if j < 3 && 2 <= i/BOARD_HEIGHT
				#横方向の動きは端を超えてできない

				next if j%3==2 && i%BOARD_HEIGHT==0
				next if j%3==0 && i%BOARD_HEIGHT==3
				#縦方向の動きは端を超えてできない

				puts "bits #{"%b" % @bits}"
				temp_board = Board.new(@bits)
				temp_piece = get_piece(i)

				from = i
				to = i+MOVE_IDX[j]

				next unless 0 <= to && to < NUM_OF_CELL
				if get_piece(to)!=B then
					next if get_piece_player(to)==player 
					temp_board.capture_piece(to)
				end
				temp_board.replace_piece(i,to)

				@next_boards.push(temp_board)

			end	
		end
		return @next_boards
		
	end	

	def view
		NUM_OF_CELL.times do |i|
			temp = "  "
			case get_piece_player(i)
			when PLAYER1
				temp[1]="1"
			when PLAYER2
				temp[1]="2"
			end

			case get_piece_type(i)
			when B
				temp = "  "
			when C
				temp[0]="c"
			when E
				temp[0]="e"
			when G
				temp[0]="g"
			when L
				temp[0]="l"
			when H
				temp[0]="h"
			end

			print "#{temp} "
			if i%4==3
				print "\n"
			end
		end
	end
			

	def put(i)
		self.bits = @next_boards[i].bits
	end

end

srv = Server.new('localhost',4444)
srv.wait
board = Board.new(srv.board)
srv.debug_print
if srv.my_turn == srv.turn then
	board.enum_next_board(srv.my_turn).each do |board|
		board.view
		puts "===="
	end
end

	

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
NUM_OF_CPIECE_CELL = 6
CPIECE_BITMASK = 0b11

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
	5 => -1,
	4 => 0,
	3 => 1,
	2 => BOARD_HEIGHT-1,
	1 => BOARD_HEIGHT,
	0 => BOARD_HEIGHT+1
}

#ビット列操作面倒だからいい具合にする
class Integer

	def slice(first,length)
		return (self >> first) & ~(-1 << length)
	end

	def overwrite(first,length,value)
		return ((self & ~(~(-1<< length)<< first )) + (value << first))
	end

end


#ソケット通信対するラッパ
class Server

	attr_reader :board, :my_turn, :turn, :request_queue

	def initialize(addr,port)
		@socket = TCPSocket.open(addr,port)
		@board = nil
		@cpiece = {}
		@my_turn = nil
		@turn = nil
		@try = false
		
		@request_queue = Queue.new
		@speaker = Thread.new do
			while request = @request_queue.deq do
				@socket.write(request)
				sleep 0.1
			end
		end
		@speaker.run
		
		@listener = Thread.new do
			while line = @socket.gets do
				#puts line
				if line =~ /--/ then
					@board = to_b(line)
					save_cpiece_position(line)
				end

				if line =~ /You are Player(\d)/ then
					@my_turn = eval("PLAYER#{$1.to_i}")
				end
				
				if line =~ /^Player(\d)/ then
					@turn = eval("PLAYER#{$1.to_i}")
				end
					
				sleep 0.1
			end
		end
		@listener.run
	end

	def request(str)
		@request_queue.enq(str)
		while @request_queue.length > 0 do
			sleep 0.1
		end
	end
	
	def save_cpiece_position(board)
		@cpiece = {}
		lines = board.split(/, /)
		if lines.length > 3 then
			lines.each.with_index do |line|
				piece = line.split(/ /)
				if piece[0] =~ /[DE]/ then
					@cpiece[piece[1]] = piece[0]
				end
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
=begin
			if type==L && col < 2 then
				if player==PLAYER1 && row==0 then
					raise "Try(PLAYER1) detected. Check the board."
				elsif player==PLAYER2 && row==3 then
					raise "Try(PLAYER2) detected. Check the board."
				end
			end
=end
#要改修
				

			if col < BOARD_WIDTH && row < BOARD_HEIGHT then
				bits += temp_bits << ((NUM_OF_CELL-col*BOARD_HEIGHT-row-1)*PIECE_LENGTH+CPIECE_AREA)
			else
				temp_bits = 0b0
				if G-type < 0 then
					raise "Lion has been taken. Check the board."
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

		puts "diff:%b" % diff
		puts "@cpiece"
		p @cpiece

		#持ち駒指し検出
		NUM_OF_PLAYER.times do |j|
			NUM_OF_CPIECE_TYPES.times do |i|
				temp_before = @board.slice(CPIECE_LENGTH*i+CPIECE_PLAYER_AREA*j,CPIECE_LENGTH)
				temp_after = board.slice(CPIECE_LENGTH*i+CPIECE_PLAYER_AREA*j,CPIECE_LENGTH)
				puts "j:#{j} i:#{i} temp_before:#{temp_before} temp_after:#{temp_after} first:#{CPIECE_LENGTH*i+CPIECE_PLAYER_AREA*j}"
				if temp_before > temp_after then
					case i
					when 0 
						from = @cpiece["g#{NUM_OF_PLAYER-j}"]
					when 1 
						from = @cpiece["e#{NUM_OF_PLAYER-j}"]
					when 2
						from = @cpiece["c#{NUM_OF_PLAYER-j}"]
					end
				end
			end
		end

		#ボード動かし検出
		NUM_OF_CELL.times do |i|
			j = NUM_OF_CELL-i-1
			if P_BITMASK & (diff >> (i*PIECE_LENGTH+CPIECE_AREA)) > 0 then
				if P_BITMASK & (board >> (i*PIECE_LENGTH+CPIECE_AREA)) == 0 then
					from = [(j/BOARD_HEIGHT+'A'.codepoints[0])].pack('U') + (j%4+1).to_s
				elsif P_BITMASK & (@board >> (i*PIECE_LENGTH+CPIECE_AREA)) == 0
					to = [(j/BOARD_HEIGHT+'A'.codepoints[0])].pack('U') + (j%4+1).to_s
				else
					to = [(j/BOARD_HEIGHT+'A'.codepoints[0])].pack('U') + (j%4+1).to_s
				end
			end
		end
		
		puts "mv #{from} #{to}"
		request("mv #{from} #{to}\n")
	end


	def debug_print
		puts "board %b\n" % @board
		puts "turn %b\n" % @turn
		puts "my_turn %b\n" % @my_turn
	end

	def initial_wait
		while @turn == nil || @board == nil || @my_turn == nil do
			request("turn\n")
			request("board\n")
			request("whoami\n")
		end
	end

	def finalize
		@socket.close
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
		return @bits.slice(first,PIECE_LENGTH)
	end

	def get_piece_player(i)
		return (get_piece(i)&P_P_BITMASK)
	end

	def get_piece_type(i)
		return (get_piece(i)&P_T_BITMASK)
	end

	def overwrite_piece(i,piece)
		raise "Can't overwrite CPIECE_AREA" unless is_board?(i)
		@bits = @bits.overwrite((NUM_OF_CELL-i-1)*PIECE_LENGTH+CPIECE_AREA,PIECE_LENGTH,piece)
	end

	def replace_piece(i,j)
		raise "Can't replace CPIECE_AREA"  unless is_board?(i) && is_board?(j)
		temp = get_piece(i)
		@bits = overwrite_piece(i,get_piece(j))
		@bits = overwrite_piece(j,temp)
	end

	def get_cpiece(i)
		raise "Can't get PIECE_AREA" if is_board?(i)
		first = (NUM_OF_CPIECE_CELL-(i-NUM_OF_CELL)-1)*CPIECE_LENGTH
		return @bits.slice(first,CPIECE_LENGTH)
	end

	def overwrite_cpiece(i,piece)
		raise "Can't overwrite PIECE_AREA" if is_board?(i)
		first = (NUM_OF_CPIECE_CELL-(i-NUM_OF_CELL)-1)*CPIECE_LENGTH
		puts "overwrite_cpiece first: #{first}"
		@bits = @bits.overwrite(first,CPIECE_LENGTH,piece)
		puts "overwrite_cpiece @bits = #{"%b" % @bits}"
	end

	def inc_cpiece(i)
		raise "Can't increment PIECE_AREA" if is_board?(i)
		temp = get_cpiece(i)
		puts "inc_cpiece temp: #{temp}"
		raise "CPIECE(#{i}) overflow" if temp > 2
		overwrite_cpiece(i,temp+1)
	end

	def dec_cpiece(i)
		raise "Can't decrement PIECE_AREA" if is_board?(i)
		temp = get_cpiece(i)
		raise "CPIECE(#{i}) underflow" if temp < 1
		overwrite_cpiece(i,temp-1)
	end

	def capture_piece(i)
		raise "Can't capture CPIECE_AREA" unless is_board?(i)

		player = (get_piece_player(i) == PLAYER1 ? 1 : 0)
		#取った逆のプレイヤーの持ち駒が増える

		pos = nil
		case get_piece_type(i)
		when C
			pos = NUM_OF_CELL
		when E
			pos = NUM_OF_CELL+1
		when G
			pos = NUM_OF_CELL+2
		when L
			puts "Lion #{i} Captured!!!"
		when H
			pos = NUM_OF_CELL
		end

		overwrite_piece(i,0b0)

		if pos !=nil then
			puts "inc_cpiece(#{pos+player*NUM_OF_CPIECE_TYPES})"
			inc_cpiece(pos+player*NUM_OF_CPIECE_TYPES)
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
			puts "MOVE[get_piece_type(i)]:#{"%9b" % MOVE[get_piece_type(i)]}"
			mesh = MOVE[get_piece_type(i)]

			if mesh == 0 then
				NUM_OF_CPIECE_TYPES.times do |j|
					j += (player == PLAYER1) ? NUM_OF_CELL : (NUM_OF_CELL + NUM_OF_CPIECE_TYPES-1)
					if get_cpiece(j)!=0 then
						temp_board = Board.new(@bits)
						temp_board.dec_cpiece(j)
						case j%3
						when 0
							temp_board.overwrite_piece(i,C+player)
						when 1
							temp_board.overwrite_piece(i,E+player)
						when 2
							temp_board.overwrite_piece(i,G+player)
						end
						@next_boards.push(temp_board)
					end
				end
			end
			#空だったら手駒を調べる

			MOVE_MESH_LENGTH.times do |j|
				j = MOVE_MESH_LENGTH - j - 1 if player != PLAYER2
				border =  [i%BOARD_HEIGHT==0,BOARD_WIDTH-1 <= i/BOARD_HEIGHT,i%BOARD_HEIGHT==BOARD_HEIGHT-1,i/BOARD_HEIGHT < 1]
				border = [border[2],border[3],border[0],border[1]] if player == PLAYER2
				#PLAYER1基準で舐めるとLSBからになる 逆は絶対インデックスによる境界判定をひっくり返す
				
				puts "j:#{j}"

				next if mesh[j].zero?
				#空だったら

				next if j%3==2 && border[0]
				next if j < 3 && border[1]
				next if j%3==0 && border[2]
				next if 5 < j && border[3]
				#時計周りに境界チェック

				puts "j:#{j} border check passed"

				temp_board = Board.new(@bits)
				temp_piece = get_piece(i)
				temp_piece_type = get_piece_type(i)

				from = i
				index = player==PLAYER1 ? j : MOVE_MESH_LENGTH-j-1
				to = i+MOVE_IDX[index]
				puts "from,to = #{from},#{to}"

				next if to < -1 || NUM_OF_CELL-1 < to 
				if get_piece(to)!=B then
					puts "get_piece_player(#{to}):#{get_piece_player(to)}"
					puts "player:#{player}"
					next if get_piece_player(to)==player 
					puts "player check passed"
					temp_board.capture_piece(to)
				end

				temp_board.replace_piece(from,to)
				if temp_piece_type == C && from%BOARD_HEIGHT==1 then
					temp_board.overwrite_piece(to,H+player)
				end

				@next_boards.push(temp_board)

			end	
		end

		return @next_boards

	end	

	def build_game_tree(player,depth)
		if depth == 0 then
			return @next_boards
		end

		return enum_next_board(player).map do |obj|
			obj.build_game_tree(player == PLAYER1 ? PLAYER2 : PLAYER1,depth-1))
		end
	end

	def view
		(NUM_OF_CELL+NUM_OF_CPIECE_TYPES*2).times do |i|
			temp = "  "
			if is_board?(i) then
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
				if i%4==3 then
					print "\n"
				end

			else
				num = get_cpiece(i)
				temp[1] = num.to_s
				case i%3
				when 0
					temp[0]="c"
				when 1
					temp[0]="e"
				when 2
					temp[0]="g"
				end
				print "#{temp} "
				if i%3==2 then
					print "\n"
				end
			end

		end
	end

end

srv = Server.new('localhost',4444)
srv.initial_wait
srv.debug_print

enemy_hands = nil
#相手着手可能手

while true do
	
	if srv.my_turn != srv.turn then

		if enemy_hands == nil then
			next_board = Board.new(srv.board)
			next_board.enum_next_board(srv.my_turn==PLAYER1 ? PLAYER2 : PLAYER1)
			enemy_hands = next_board.next_boards.map{|obj| obj.bits}
			#初期例外
		end

		while srv.my_turn != srv.turn do
			srv.request("turn\n")
		end

		board = srv.board
		while (srv.board ^ board) == 0 do
			srv.request("board\n")
		end
		raise "Rule infringement detected" if enemy_hands && !enemy_hands.index(srv.board)
	end

	board_now = Board.new(srv.board)
	board_now.enum_next_board(srv.my_turn)
	next_move = board_now.next_boards
	
	next_move.each do |obj|
		obj.view
		puts "==========="
	end

	next_board = next_move[rand(next_move.length)-1]
	next_board.view
	puts "========"
	srv.to_mv(next_board.bits)

	next_board.enum_next_board(srv.my_turn==PLAYER1 ? PLAYER2 : PLAYER1)
	enemy_hands = next_board.next_boards.map{|obj| obj.bits}

	p next_board.build_game_tree(srv.my_turn==PLAYER1 ? PLAYER2 : PLAYER1,5)
	#深さ5のゲーム木生成

	count = 0
	srv.request("turn\n")
	srv.request("board\n")
	while srv.my_turn == srv.turn do
		srv.request("turn\n")
		srv.request("board\n")
		count+=1
		if count > 10 then
			srv.to_mv(next_board.bits)
		end
	end
end

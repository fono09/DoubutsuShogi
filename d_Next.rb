require 'socket'
require 'activerecord'
require 'redis-objects'

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

INITIAL_BOARD = 0b101100000000001011001001000101001010000000000011000000000000


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

#探索深さ
DEPTH = 6

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
		@tried = { 
			PLAYER1 => false,
			PLAYER2 => false
		}
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

			if type==L && col < 3 then
				if player==PLAYER2 && row==3 then
					raise "PLAYER1 tried. Check the board." if @tried[PLAYER1]
					@tried[PLAYER1]=true
				elsif player==PLAYER1 && row==0 then
					raise "PLAYER2 tried. Check the board." if @tried[PLAYER2]
					@tried[PLAYER2]=true
				end
			end

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

		#持ち駒指し検出
		NUM_OF_PLAYER.times do |j|
			NUM_OF_CPIECE_TYPES.times do |i|
				temp_before = @board.slice(CPIECE_LENGTH*i+CPIECE_PLAYER_AREA*j,CPIECE_LENGTH)
				temp_after = board.slice(CPIECE_LENGTH*i+CPIECE_PLAYER_AREA*j,CPIECE_LENGTH)
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

#Redis記憶用
class Record_Board < ActiveRecord::Base
	include Redis::Objects

end

#ボードビット列に対する操作
class Board

	attr_reader :bits, :next_boards
	attr_accessor :prev_board
	#:rotated,

	def initialize(bits,prev)
		@bits = bits
		#@rotated = [0,0]
		@prev_board = prev
		@next_boards = nil
		@last = false
		@lose = {
			PLAYER1 => false,
			PLAYER2 => false
		}
		if tried(PLAYER1) || tried(PLAYER2) then
			if @prev_board && (@prev_board.tried(PLAYER1) || @prev_board.tried(PLAYER2)) then
				@lose[PLAYER1] = true if @prev_board.tried(PLAYER1)
				@lose[PLAYER2] = true if @prev_board.tried(PLAYER2)
				@last = true
			end
		end
		if lose(PLAYER1) || lose(PLAYER2) then
			@lose[PLAYER1] = lose(PLAYER1)
			@lose[PLAYER2] = lose(PLAYER2)
			@last = true
		end
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
		@bits = @bits.overwrite(first,CPIECE_LENGTH,piece)
	end

	def inc_cpiece(i)
		raise "Can't increment PIECE_AREA" if is_board?(i)
		temp = get_cpiece(i)
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
			@last = true
		when H
			pos = NUM_OF_CELL
		end

		overwrite_piece(i,0b0)

		if pos !=nil then
			inc_cpiece(pos+player*NUM_OF_CPIECE_TYPES)
		end
	end

	def get_piece_efficacy(i)
		piece = get_piece(i)
		player = get_piece_player(i)
		idx = Array.new
		MOVE_MESH_LENGTH.times do |j|
			j = MOVE_MESH_LENGTH - j - i if plyaer != PLAYER2
			border = [i%BOARD_HEIGHT==0, BOARD_WIDTH-1<=i/BOARD_HEIGHT,
				i%BOARD_HEIGHT== BOARD_HEIGHT-1,i/BOARD_HEIGHT <1]
			boarder = [boarder[2],boarder[3],border[0],border[1]] if player == PLAYER2
			#PLAYER2基準ではひっくり返す

			next if mesh[j].zero?
			#空なら次

			next if j%3==2 && border[0]
			next if j < 3 && border[1]
			next if j%3==0 && border[2]
			next if 5 < j && border[3]
			#時計周りに境界チェック
			
			from = i
			index = player==PLAYER1 ? j : MOVE_MESH_LENGTH-j-1
			to = i+MOVE_IDX[index]

			next if to < -1 || NUM_OF_CELL-1 < to
			idx.push(to)
		end

		return idx
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
		@next_boards = []
		NUM_OF_CELL.times do |i|

			if get_piece(i) == B then
				NUM_OF_CPIECE_TYPES.times do |j|
					j += (player == PLAYER1) ? NUM_OF_CELL : (NUM_OF_CELL + NUM_OF_CPIECE_TYPES)
					if get_cpiece(j)!=0 then
						temp_board = Board.new(@bits,self)
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
			#空だったら手駒を置けるか調べる

			next unless get_piece_player(i) == player
			mesh = MOVE[get_piece_type(i)]
			#ここからは盤面上の駒を動かす

			MOVE_MESH_LENGTH.times do |j|
				j = MOVE_MESH_LENGTH - j - 1 if player != PLAYER2
				border =  [i%BOARD_HEIGHT==0,BOARD_WIDTH-1 <= i/BOARD_HEIGHT,i%BOARD_HEIGHT==BOARD_HEIGHT-1,i/BOARD_HEIGHT < 1]
				border = [border[2],border[3],border[0],border[1]] if player == PLAYER2
				#PLAYER1基準で舐めるとLSBからになる 逆は絶対インデックスによる境界判定をひっくり返す
				
				next if mesh[j].zero?
				#空だったら

				next if j%3==2 && border[0]
				next if j < 3 && border[1]
				next if j%3==0 && border[2]
				next if 5 < j && border[3]
				#時計周りに境界チェック

				temp_board = Board.new(@bits,self)
				temp_piece = get_piece(i)
				temp_piece_type = get_piece_type(i)

				from = i
				index = player==PLAYER1 ? j : MOVE_MESH_LENGTH-j-1
				to = i+MOVE_IDX[index]

				next if to < -1 || NUM_OF_CELL-1 < to 
				if get_piece(to)!=B then
					next if get_piece_player(to)==player 
					temp_board.capture_piece(to)
				end

				temp_board.replace_piece(from,to)
				flag = false
				if temp_piece_type == C then
					case player
					when PLAYER1
						flag = true if from%BOARD_HEIGHT==1  && to%BOARD_HEIGHT==0
					when PLAYER2
						flag = true if from%BOARD_HEIGHT==2 && to%BOARD_HEIGHT==3
					end
				end
				temp_board.overwrite_piece(to,H+player) if flag

				@next_boards.push(temp_board)

			end	
		end

		return @next_boards

	end	

	def last
		count = 0
		NUM_OF_CELL.times do |i|
			count+=1 if get_piece_type(i) == L
		end
		return count < 2 ? true : false
	end

	def tried(player)
		enemy = player==PLAYER1 ? PLAYER2 : PLAYER1
		temp = nil
		3.times do |i|
			j = player==PLAYER1 ? i*4+3 : i*4
			temp =  get_piece_type(j) == L && get_piece_player(j) == enemy
		end
		return temp
	end

	def lose(player)
		return @lose[player] if @lose[player]
		#trueになったらもうそれだけ

		temp = true
		NUM_OF_CELL.times do |i|
			if get_piece_player(i) == (player == PLAYER1 ? PLAYER1 : PLAYER2) && get_piece_type(i) == L then
				temp = false
			end
		end

		@lose[player] = true if temp == true
		@last = true if temp == true
		return temp
	end

	def evalute(player,gene)

		statistics = []
		NUM_OF_CPIECE_TYPES.times do |i|
			case player
			when PLAYER1
				statistics.push(get_cpiece(NUM_OF_CELL+i))
			when PLAYER2
				statistics.push(get_cpiece(NUM_OF_CELL+NUM_OF_CPIECE_TYPES+i))
			end
		end
		#持ち駒タイプ別カウント
		
		temp={C=>0,E=>0,G=>0,L=>0,H=>0}
		NUM_OF_CELL.times do |i|
			if get_piece_player(i) == player && get_piece(i) != B then
				temp[get_piece_type(i)]+=1
			end
		end
		i = nil
		[C,E,G,L,H].each do |key|
			statistics.push(temp[key])
		end
		#盤面タイプ別カウント
		
		statistics.push(@next_boards ? @next_boards.length : 0)
		#次手番の数

		puts "statistics.length : #{statistics.length}"
		puts "gene : #{gene.inspect}"
		
		length = statistics.length - gene.length
		if length > 0 then
			statistics.pop(length)
		elsif length < 0 then
			gene.pop(-1*length)
		end
		
		value = gene.zip(statistics).map do |piece|
			piece.inject(1,:*)
		end.inject(0,:+)
		puts "value : #{value}"
		#遺伝子は係数x_nのリスト
		#掛けて足してそれが評価値

		return value

	end

	def nega_max(player,depth)
		gene = [1,1,1,1,1,1,1,1,1,1,1,1,1,1]
		return evalute(player,gene) if depth == 0
		return evalute(player,gene) if @last
		return evalute(player,gene) unless @next_boards

		enemy = player==PLAYER1 ? PLAYER2 : PLAYER1
		max = -10**10
		@next_boards.each do |obj|
			score = -1*obj.nega_max(enemy,depth-1)
			max = score if score > max
		end
		return max
	end

	def build_game_tree(player,depth)

		enum_next_board(player) unless @next_boards

		if depth == 0 || @last == true then
			return
		end

		@next_boards.each do |obj|
			build_game_tree(player==PLAYER1 ? PLAYER2 : PLAYER1,depth-1)
		end
		
	end

	def get_best_hand(player,depth)

		return @next_boards.max_by do |obj|
			obj.nega_max(player,depth)
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

class Player
end

class AI < Player
end

srv = Server.new('localhost',4444)
srv.initial_wait
srv.debug_print

root = Board.new(INITIAL_BOARD,nil)
root.build_game_tree(PLAYER1,DEPTH)
#ゲーム木生成

initial_flag = (srv.my_turn==PLAYER1) ? true : false

while true do

	srv.request("turn\n")
	while srv.my_turn != srv.turn do
		srv.request("turn\n")
	end
	
	unless initial_flag then
		srv.request("board\n")
		puts "=====Enemy Turn====="
		index = root.next_boards.map do |obj|
				obj.view
				puts obj.bits
				puts "==========="
				obj.bits
			end.index(srv.board)
		puts srv.board
		puts "index : #{index}"
		raise "Rule infringement detected" unless index
		puts "=====Enemy Determinated===="
		root = root.next_boards[index]
		puts root.view
		puts "=========="
		root.prev_board = nil
		root.build_game_tree(srv.my_turn,DEPTH)
	else
		initial_flag = false
	end


	next_boards = root.next_boards
	puts "=====My Turn====="
	next_boards.each do |obj|
		obj.view
		puts "=========="
	end

	next_board = nil
	next_boards.each do |obj|
		next_board = obj if obj.lose(srv.my_turn == PLAYER1 ? PLAYER2 : PLAYER1)
	end unless next_board
	#相手が負ける手があれば確実に打つ
		
	next_board = root.get_best_hand(srv.my_turn,DEPTH) unless next_board
	#それがなければ最良手

	next_board = next_boards[rand(next_boards.length)-1] unless next_board
	#最後の砦デバッグランダム
	
	next_board.view
	puts "====Determinated===="
	srv.to_mv(next_board.bits)
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

	root = next_board
	root.prev_board = nil
	root.build_game_tree(srv.my_turn==PLAYER1 ? PLAYER2 : PLAYER1,DEPTH)
	
end

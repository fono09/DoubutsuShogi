require 'socket'

#スレッド内例外で落とす
Thread.abort_on_exception = true

######## 内部棋譜ビットマップ#######
# 0b 4 * 12 bits(盤面) + 2 * 6 bits(持ち駒) = 60 bits

BOARD_HEIGHT = 4
BOARD_WIDTH = 3

BOARD_AREA = 48
PIECE_LENGTH = 4
NUM_OF_CELL = BOARD_AREA/PIECE_LENGTH
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

#ビット列操作面倒だからいい具合にする
class Fixnum
	
	def slice(first,last)
		return self.to_s(2)[(-last-1)..(-first-1)].to_i(2)
	end

	def replace(first,last,value)
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
				if line =~ /You are Player(\b)/ then
					@my_turn = $1.to_i
				end

			}],
			["turn\n",Proc.new{|line|
				if line =~ /^Player(\d)$/ then
					@turn = $1.to_i
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
				bits += temp_bits << (col*BOARD_HEIGHT+row)*PIECE_LENGTH+CPIECE_AREA
			else
				temp_bits = 0b0
				if G-type < 0 then
					raise "LION has been taken. Check the board."
				end
				temp_bits += 0b1 << (G-type)*CPIECE_LENGTH
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
					
end

#ビット列に対する操作
class Board
	attr_reader :bits
	def initialize(bits)
		@bits = bits
	end

	def swap(axis)


	end

	def swap!(axis)

	end

	def put(i)
	end

	def put!(i)
	end

	def next_states(i)
	end
end

srv = Server.new('localhost',4444)
while srv.board == nil || srv.turn == nil do
	sleep 0.01
end
print srv.board,srv.turn

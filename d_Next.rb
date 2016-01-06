require 'socket'

#スレッド内例外で落とす
Thread.abort_on_exception = true

#ビット列操作面倒だからいい具合にする
class Integer

	def slice(first,length)
		return (self >> first) & ~(-1 << length)
	end

	def overwrite(first,length,value)
		return ((self & ~(~(-1<< length)<< first )) + (value << first))
	end

end

class Server

	def initialize(addr: addr,port: port)
		@socket = TCPSocket.open(addr,port)
		@request_queue = Queue.new
		@responce_queue = Queue.new
		@talker = Thread.new do
			while request = @request_queue.deq do
				@socket.write(request)
				sleep 0.1
				@responce_queue.enq(@socket.gets)
			end
		end
		@talker.run
	end

	def request(str)
		@reqeust_queue.enq(str)
		while @request_queue.length > 0 do
			sleep 0.1
		end
		return @responce_queue.deq
	end

end

class Converter
end

class Piece
end

class Board
end

class State
end

class Player
end

class AI
end


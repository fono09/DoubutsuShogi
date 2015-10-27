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

num = 13940987084
puts "input"
puts "%b"%num
puts "slice(0,4)"
puts "%b" % num.slice(0,4)
puts "replace(0,4,0b1111)"
puts "%b" % num.replace(0,4,0b1111)



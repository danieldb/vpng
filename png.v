
module png
import os
import math
import compress.zlib


struct PNG {
	pub mut: 
		image []u8

		width u32
		height u32
		bit_depth u8
		color_type u8
		compression_method u8
		filter_method u8
		interlace_method u8

		colors [][][]u8
}

pub fn load_png(path string) &PNG {

mut png := &PNG{}

png.image = os.read_bytes(path) or { panic(err) }

mut skip_count := 0
mut rgb_palette := [][]u8{}
mut rgba_palette := [][]u8{}
mut use_rgba := false
//IMPORTANT
/*
This for loop iterates through the image hex chunk by chunk
first, it looks at chunk length, the first unsigned 4 byte int
then it looks for chunk type and does fancy stuff, using the chunk length to know how long it is
next, it disregards the crc (cyclical redundancy check) because I dont care about corruption rn (note: it still counts those bytes though)
after this, the number of bytes counted is the skip cound which then moves through the remaining hex to the next chunk

*/
for i, v in png.image {
	if skip_count > 0 {
		skip_count -= 1
		continue
	}
	// png init chunk
	if i == 0 {
		for j in 0..8 {
			print("${png.image[j]} ")
		}
		println('')
		skip_count = 7
		continue
	}
	mut chunk_length := 0
	print("cl: ")
	mut skip := 0
	// chunk length
	for j in 0..4 {
		chunk_length += int(png.image[i+j] * math.pow(256, 3-j))
		print("${int(png.image[i+j]):X}")
		skip += 1
	}
	mut chunk_type := ''
	print(" | $chunk_length | ctc: ")
	//chunk type
	for j in 4..8 {
		chunk_type += "${int(png.image[i+j]):c}"
		print("${int(png.image[i+j]):X} ")
		skip += 1
	}
	print(" | $chunk_type | data: ")
	// image data chunk id
	if chunk_type == "IHDR" {
		for j in 8..12 { png.width += u32(png.image[j+i] * math.pow(256, 11-j)) }
		for j in 12..16 { png.height += u32(png.image[j+i] * math.pow(256, 15-j)) }
		for j in 16..17 { png.bit_depth = png.image[j+i] }
		for j in 17..18 { png.color_type = png.image[j+i] }
		for j in 18..19 { png.compression_method = png.image[j+i] }
		for j in 20..21 { png.interlace_method = png.image[j+i] }
		for j in 19..20 { png.filter_method = png.image[j+i] }
		print("\n  width: $png.width")
		print("\n  height: $png.height")
		print("\n  bit depth: $png.bit_depth")
		print("\n  color type: $png.color_type")
		print("\n  compression method: $png.compression_method")
		print("\n  filter method: $png.filter_method")
		print("\n  interlace method: $png.interlace_method")
		
		if png.compression_method != 0 { panic("invalid compression method") }
		if png.filter_method != 0 { panic("invalid filter method") }
		if png.color_type != 6 && png.color_type != 3 { panic("only truecolor with alpha and indexed color supported") }
		if png.bit_depth != 8 { panic("only bit depth of 8 supported") }
		if png.interlace_method != 0 { panic("interlacing unsupported") }

		png.colors = [][][]u8{init: [][]u8{len: int(png.height), init: [u8(0), u8(0), u8(0), u8(255)]}, len: int(png.width)}
	}
	mut chunk_data := []u8{}
	// chunk data
	for j in 8..(8+chunk_length) {
		chunk_data.insert(j-8, png.image[i+j])
		print("${int(png.image[i+j]):X} ")
		skip += 1
	}
	if chunk_type == "PLTE" {
		if chunk_length % 3 != 0 {panic("PLTE chunk length should be divisible by 3 and is not")}
		for j in 0..chunk_length/3 {
			rgb_palette.insert(rgb_palette.len, [chunk_data[3*j], chunk_data[3*j+1], chunk_data[3*j+2]])
		}
		print(rgb_palette)
	}
	if chunk_type == "tRNS" {
		if chunk_length != rgb_palette.len {panic("tRNS and PLTE do not contain the same number of entries")}
		use_rgba = true
		for j in 0..chunk_length{
			rgba_palette.insert(rgba_palette.len, [rgb_palette[j][0], rgb_palette[j][1], rgb_palette[j][2], chunk_data[j]])
		}
		print("\n RGBA PALETTE \n")
		for j in rgba_palette {
			print("${int(j[0]):X} ${int(j[1]):X} ${int(j[2]):X} ${int(j[3]):X} \n")
		}
	}
	// plte correspondances
	if chunk_type == "IDAT" && png.color_type == 3 {
		recon_plte := parse_encoded_idat(png.width, png.height, mut chunk_data, 1)
		print(recon_plte)
		for h in 0..png.height{
			for w in 0..png.width{
				for l in 0..4{
					if use_rgba {
						png.colors[h][w][l] = rgba_palette[recon_plte[h * png.width + w]][l]
					}else{
						if l == 3 {
							png.colors[h][w][l] = 255
							continue
						} 
						png.colors[h][w][l] = rgb_palette[recon_plte[h * png.width + w]][l]
					}
				}
			}
		}
	}
	// image rgba pairs
	if chunk_type == "IDAT" && png.color_type == 6 {
		recon_truecolor := parse_encoded_idat(png.width, png.height, mut chunk_data, 4)
		print(recon_truecolor)
		for h in 0..png.height{
			for w in 0..png.width{
				for l in 0..4{
					png.colors[h][w][l] = recon_truecolor[h * 4 * png.width + 4 * w + l]
				}
			}
		}
		//print('\n\n ${recon} \n\n')
	}
	// crc checksum thing (i cant be bothered)
	print("\n  crc: ")
	for j in (8+chunk_length)..(12+chunk_length) {
		print("${int(png.image[i+j]):X} ")
		skip += 1
	}
	println('')
	skip_count = skip-1
}
//print(png.colors)
return png
}

fn paeth_predictor(a u8, b u8, c u8) f32 {
	mut pr := f32(0)
	mut p := a + b - c
	mut pa := math.abs(p - a)
	mut pb := math.abs(p - b)
	mut pc := math.abs(p - c)
	if pa <= pb && pa <= pc{
		pr = a
	}
	else if pb <= pc{
		pr = b
	}
	else{
		pr = c
	}
    return pr
}

fn recon_a(r u32, c int, width u32, recon []u8, stride int, bytes_per_pixel int) u8 {
	return if c >= bytes_per_pixel { recon[int(r) * stride + c - bytes_per_pixel] } else { 0 } 
}
fn recon_b(r u32, c int, width u32, recon []u8, stride int, bytes_per_pixel int) u8 {
	return if r > 0 { recon[(int(r)-1) * stride + c] } else { 0 }
}
fn recon_c(r u32, c int, width u32, recon []u8, stride int, bytes_per_pixel int) u8 {
	return if r > 0 && c >= bytes_per_pixel {recon[(int(r)-1) * stride + c - bytes_per_pixel]} else { 0 } 
}
fn parse_encoded_idat(width u32, height u32, mut chunk_data []u8, bytes_per_pixel u8) []u8 {
	chunk_data = zlib.decompress(chunk_data) or {panic("couldnt decompress")}
	
	mut recon := []u8{}
	mut ii := 0

	stride := int(width) * bytes_per_pixel	
	for r in 0..height{ // for each scanline
		filter_type := chunk_data[ii] // first byte of scanline is filter type
		ii += 1
		for c in 0..stride{ // for each byte in scanline
			filt_x := chunk_data[ii]
			mut recon_x := u8(0)
			ii += 1
			if filter_type == 0{ // None
				recon_x = filt_x
				print("filt: 0    res: ${int(recon_x)} \n")
			}else if filter_type == 1{ // Sub
				recon_x = u8(filt_x + recon_a(r, c, png.width, recon, stride, bytes_per_pixel))
				print("filt: 1    res: ${int(recon_x)} \n")
			}else if filter_type == 2{ // Up
				recon_x = u8(filt_x + recon_b(r, c, png.width, recon, stride, bytes_per_pixel))
				print("filt: 2    res: ${int(recon_x)} \n")
			}else if filter_type == 3{ // Average
				recon_x = u8(filt_x + (recon_a(r, c, png.width, recon, stride, bytes_per_pixel) + recon_b(r, c, png.width, recon, stride, bytes_per_pixel))) // 2
				print("filt: 3    res: ${int(recon_x)} \n")
			}else if filter_type == 4{ // Paeth
				recon_x = u8(filt_x + paeth_predictor(recon_a(r, c, png.width, recon, stride, bytes_per_pixel), recon_b(r, c, png.width, recon, stride, bytes_per_pixel), recon_c(r, c, png.width, recon, stride, bytes_per_pixel)))
				print("filt: 4    res: ${int(recon_x)} \n")
			}else{
				panic('unknown filter type: $filter_type \n')
			}
		recon.insert(recon.len, u8(recon_x & 0xff)) // truncation to byte
		}
	}
	
	return recon
}


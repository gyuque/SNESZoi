(function(aGlobal) {
	'use strict';
//	var NCOLORS = 15;
	var NCOLORS = 10;
	var gColorsInput = null;

	window.onload = function() {
		initColorInput('in-colors');
		observeDropArea('drop-area');
	};

	function initColorInput(eid) {
		var el = document.getElementById(eid);
		el.value = NCOLORS;
		gColorsInput = el;
	}

	function observeDropArea(eid) {
		var el = document.getElementById(eid);
		function cancel_func(e) {
			e.preventDefault();
			e.stopPropagation();
			return false;
		}

		el.addEventListener('dragenter', cancel_func, false);
		el.addEventListener('dragover', cancel_func, false);

		el.addEventListener('drop', function(e) {
			var file = e.dataTransfer.files[0];

			var fileReader = new FileReader();
			fileReader.onload = function(le) {
				var img = new Image();
				img.onload = function() { afterImageLoad(img); };
				img.src = le.target.result;

				el.style.display = "none";
			};

			fileReader.readAsDataURL(file);
			cancel_func(e);
		}, false);
	}

	function afterImageLoad(loadedImage) {
		NCOLORS = parseInt(gColorsInput.value, 10);

		var cv = document.getElementById('cv1');
		cv.width = loadedImage.width;
		cv.height = loadedImage.height;
		cv.style.backgroundColor = '#258';

		var g = cv.getContext('2d');
		g.drawImage(loadedImage, 0, 0);

		var palEntries = [];

		var imageData = g.getImageData(0, 0, cv.width, cv.height);
		var paletteFileBytes = pickPalette(imageData.data, palEntries);
		exportPaletteFile(paletteFileBytes);
		var indexedImage = pickPixels(imageData.data, cv.width, cv.height, palEntries); 

		var outG = document.getElementById('cv-out').getContext('2d');
		dumpIndexedImage(outG, cv.width, cv.height, indexedImage, palEntries);
		generatePlanarImage(cv.width, cv.height, indexedImage);
	}

	function dumpIndexedImage(g, w, h, indices, pal) {
		var pos = 0;
		for (var y = 0;y < h;++y) {
			for (var x = 0;x < w;++x) {
				var i = indices[pos++];
				var pe = pal[i];
				g.fillStyle = 'rgb(' + pe.r +','+ pe.g +','+ pe.b +')';
				g.fillRect(x, y, 1, 1);
			}
		}
	}

	function generatePlanarImage(w, h, indices) {
		var planes = [ [],[],[],[] ];
		var np = planes.length;

		var readPos = 0;
		for (var y = 0;y < h;++y) {
			for (var x = 0;x < w;++x) {
				var k = indices[readPos++];
				
				var tmpDigits = [];
				for (var j = 0;j < np;++j) {
					var bit = (k >> j) & 1;
					
					planes[j].push(bit);
				}
			}
		}

		arrangeTiles(planes, w, h);
	}

	function arrangeTiles(planeArray, imageWidth, imageHeight) {
		var cols = imageWidth >> 3;
		var rows = imageHeight >> 3;
		var i;

		var outBytes = [];

		for (var cy = 0;cy < rows;++cy) {
			for (var cx = 0;cx < cols;++cx) {
				var ox = cx * 8;
				var oy = cy * 8;

				var rows1 = [];
				var rows2 = [];
				for (var y = 0;y < 8;++y) {
					var origin = (oy+y) * imageWidth + ox;
					rows1.push( pack8Bits(planeArray[0], origin) );
					rows1.push( pack8Bits(planeArray[1], origin) );
					rows2.push( pack8Bits(planeArray[2], origin) );
					rows2.push( pack8Bits(planeArray[3], origin) );
				}

				for (i in rows1) {
					outBytes.push(rows1[i]);
				}

				for (i in rows2) {
					outBytes.push(rows2[i]);
				}
			}
		}

		emitBitmapLink( rawimageToDataURL(outBytes) );
	}

	function emitBitmapLink(url) {
		var a = document.getElementById('dl-link');
		a.innerHTML = 'Save Bitmap';
		a.setAttribute('download', 'snes-pattern.bin');
		a.href = url;
	}

	function pack8Bits(srcArray, startPos) {
		var packed = 0;
		for (var k = 0;k < 8;++k) {
			var val = srcArray[startPos + k];
			packed |= val << (7-k);
		}

		return packed;
	}

	function to16BitPair(p1, p2) {
		var len = p1.length;

		var ret = [];
		for (var i = 0;i < len;++i) {
			var hi = p1[i];
			var lo = p2[i];
			ret.push( (hi << 8) | lo );
		}

		return ret;
	}

	function rawimageToDataURL(bytes) {
		var parts = [];

		for (var i = 0;i < bytes.length;++i) {
			parts.push( toPercentHex(bytes[i]) );
		}

		return 'data:application/octet-stream,' + parts.join('');
	}

	function toPercentHex(b) {
		var h = b.toString(16);
		if (h.length < 2) { h = '0'+h; }

		return '%' + h;
	}

	function pickPalette(pixels, outArray) {

		var lines = [];
		var binBytes = [];
		for (var i = 0;i < NCOLORS;++i) {
			var cR = pixels[i*4  ];
			var cG = pixels[i*4+1];
			var cB = pixels[i*4+2];

			outArray.push({
				r: cR,
				g: cG,
				b: cB
			});

			var r5 = to5bits(cR);
			var g5 = to5bits(cG);
			var b5 = to5bits(cB);

			var c16 = r5 | (g5 << 5) | (b5 << 10);

			/*
			lines.push('lda #$' + (c16 & 0xff).toString(16));
			lines.push('sta $2122');
			lines.push('lda #$' + (c16 >> 8).toString(16));
			lines.push('sta $2122');
			lines.push('');
			*/

			binBytes.push(c16 & 0xff);
			binBytes.push(c16 >> 8);
		}

		return binBytes;
	}

	function exportPaletteFile(paletteFileBytes) {
		var entireBytes = 32;
		var outBytes = [];

		for (var i = 0;i < entireBytes;++i) {
			if (i < paletteFileBytes.length) {
				outBytes.push(paletteFileBytes[i]);
			} else {
				outBytes.push(0);
			}
		}

		var a = document.getElementById('pal-dl-link');
		a.innerHTML = "Save Palette";
		a.setAttribute('download', 'palette-data.bin');
		a.href = rawimageToDataURL(outBytes);
	}

	function pickPixels(pixels, w, h, paletteArray) {
		var indexBuffer = [];

		var pos = 0;
		for (var y = 0;y < h;++y) {
			for (var x = 0;x < w;++x) {
				var cR = pixels[pos++];
				var cG = pixels[pos++];
				var cB = pixels[pos++];
				var cA = pixels[pos++];

				var palIndex = 0;
				if (y > 0 || x > NCOLORS) {
					palIndex = findEntry(cR, cG, cB, paletteArray);
				}

				indexBuffer.push(palIndex);
			}
		}

		return indexBuffer;
	}

	function findEntry(r, g, b, arr) {
		for (var i in arr) {
			var dr = r - arr[i].r;
			var dg = g - arr[i].g;
			var db = b - arr[i].b;

			if ((dr*dr + dg*dg + db*db) < 8) {
				return i - 0;
			}
		}

		return 0;
	}


	function to5bits(clr) {
		return (clr >> 3);
	}

	var kImageData = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAAAgBAMAAAAoDG0WAAAAMFBMVEX/AP9IMxpYRz2EYzGle0rOpWPntXP////AwMCAgIDf399BQUH///////////////9jwuDaAAABk0lEQVR42s2UvWrDMBRG07qFhLxEiPMAxTZ0DbWM11Lc5+hi0NoxytRRFw3pmGbqWKHBz2UyuJ9iO3Y3yVOvwCiBe3LujzO7CbM3vZ/9s9gf96fT8TQ5fy6l/NqJ3edUgBCS7NlNBUgioZUUcrIBEdWHA7kC7l+v8dwBBJ0BoHc3wF2WFaxgGSuK7eULCIhG4/nhCGAIMBDbzkBTXaOLrgY2NYwGgMKv14q0cjQIcp7zl03OyvKhNVAkTHUg7WzAy7xkHIC+BNJN497EIGXIZjzvS0D7SNXkPgXGIJCXOU+7EkhR9aPcDZJH3jpcpwABGBjnMSI5K61HC5hjjMZInxL6MbYlLOwi1e6LFKQxS542KUvT3kBgk8h5jEEc4sQRztWgnYKjwSXCaLgvMIBKYRV9AMkYYF9nSNC3B2ATD/clytcGFC/A2ADp2AOtfADJemygsUjogQ9g3MSlHcJZkfLInyV/e1BRo8j4AOKxgbYzJOVjcLsOVwPA2D9EdNKrBdF6BOjCp4TVavRBaYOjffKnxy8vsNmaaux+YAAAAABJRU5ErkJggg==";
	var kImageData2 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAIBAMAAABqq+CcAAAAMFBMVEUtPUpVaYBjGEqFmqmoucTE09////////8AAAD////////////////////////////HPA3CAAAAPUlEQVR42mNoEHbNYAQCQSAwBgKGDiAAcRiAAEyDBISBAEXAEAhQBMB68Qq4AAHQGgFhY2NDsEAoEMBUAABf7Rj6DQVuwQAAAABJRU5ErkJggg==";
	var kImageData3 =  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAABABAMAAAAg+GJMAAAAMFBMVEUYIUpSY85jGEpzYwh7jOeEc2O1Wim9vf/e3ufvvZT3Wkr/hIT/3rX/54T///////99c5+sAAACcUlEQVR42u3XsWsTURzA8auTa5dWJ0uaBHERDBYcOhhCL1cFQQx0U2o5CMSlPLhsBwVJSKk3JBw82kMoIvgydBGUZKiDBA5OHFw85f4MMYgQT3Tw997v9xMrQgcfZAjfe59773IJOWtp8VHzzfDOlcIJh3XSif+B0wzUavzxRrf0zgtmh0BRCNtePyTnIx0Ctt1pe2JMLgLpACja7c++793wqsQCkA6Btte55Xvrz7cJAOkAsH2vU68L8YJYAdY1wBGeLcSTbQowOwTqzvxgviaKFFB3nMEAdgjY1+fiswuiSG3BdmQch6ADoLZ1bjHxF6oUUNs6L5NkUiWBtddv55IL+QH4/Ly/shILdg04SPIzFGjA7PA+cG8mcRIWiB2gHd7Ka80DN94skAPp2rex3JRugRlm14BS6N7mALNDoHQ3lg1GQDoAShvHXx9/eUjPRzoANoLd2exoSi4B6xCYTV92FQMg/VegNB71guPeVQpAOwCCT3u7H/dWNikA6wBoNFaDIwbAOrgGzXD1fTdbIT8FrOvAB5WygNEhcD8a7z9jAKTrgEwlCxhdA2SasYDZdSDiV2B2CExklKV9GkA6AFqTKMuydySAdQCUH2QsgHUALH8/QZSSfzqxDoE8swDSNSCNMskBZte2kB/Ql8wWzA5/E6/1I1mpkBcR6xBYrlQq9H2Edu1n3c0HAyBdA5phOeQAs2tA6zdA658Df72F2c7lKQeYXQOCnYssYHYN6PZU95ABzA6BSyOlRgyAdAgMx0oNRzSAdAAsKfXUVeoMNR/rALBc917+Ih+DsA7f/BwkgHS4hR+d3gLST99j3x8D3wABkRxXXn82ZwAAAABJRU5ErkJggg==";
	var kImageAoba1Data = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAACABAMAAAAxEHz4AAAAMFBMVEVWYsnEAACAjOOxYCnmmWDqvpP83LFhHU3//4T////Z3+gA/4AyN3iAAAAAAAC5uf/LGrRcAAAD0klEQVR42u3WTWskRRgH8LLFPdVlPDtSdlgHIdCSptOXBE/7CYbZvSgIYXNbhPShSOi4X0EUhB2ErHMJE5R8habDMrDUZXbRQKDx6G2ROig7IONT1S/1PO1OzAuih67Dsv/+P/Xr14Sw1Ft8c+/R+/Kmi914Zwd0wBuAPX9Ajl85szr7ZOLquQKCwNcaDVw9W+DwhV4sT5fNKa6TLTB/sZwuj470eTVwnWyBP989nWo40K8GII9fn5Lc7qd6OrXZAI+Pfjla6Mlp8EHZmzxeBCS3+4VefGSzAfYnwdfLQC+DoBzYnywmOgi0y+0e8l2IQQPoyW/vCM8NvA4Eye0eZQMcaK35nU+fflINQA5aWa/MJbAmnv7+xVcbf9QD18glsPnhd3c+/9YN0Cwvy/Yt+Jt3d2HVA+0MG1ZnCwzWNnZ37z9sgMHaGs5S057kEtgLR49+Hu41QJXrb1fTnuQSkDIcDWMHVLkBaG/zZy9jApyFsawHdJV96TbgnuQKSPPvf3CAtFkNHGDyDAFuvgLyvPdePfDYhx4ymznAZI4AN18Cqb/+Fq8H4NYzkxFge5bTzBtAD3LBn+d8Vn6qcAE+M5nL+rvIbXYAmmd2R87Yc8GbM6bC5hrYG7R6OGGTy9+J+brHvWaDzH1usruHVg8DGWQHpIL7BBCKAGkJIkC0AJ8Aqd8GxN8Blq++gtTjqQX4qivIfN4CMgJks8xTOQJE5vEcAeADIDHAYLweSNQsEypf52f1PCuzdJfAISNAZcqsGhjOcnPkLKwBZbNyQPpsq4qs3KHMQFwDO1IpxlUSNqLNsQNU9DEBdpQQzA3EMvMEfChOVJ6HevhZeXvDw8AW833PfWnwGH34mptseiFwzwQjXyKcQAhFALIBeo+R7HseAbLWFSjmcwSqDHyczR0rDNiFAXgHW+iZwQrD2ZtyCaRhuBWGbgP8xgoj9NBNH+2QWkUPYwdISHhAJveHGGj3UEsKbLaBXQq0eqgtcimA76jd27NHBABxSHZQIBnFuI9GtwOSkfl/8g9AfBlgymSM30IbiIbHq4GDsSn3MfDkuMrNzBMCwBbUl8DBuHDA9Bgy3nFBktmC+uLk3Pw7L84b4OTH6mi1Di9wslsuTlyam78Qi16/AQ77hZz30ZakmFNg3kf9ds8CxU9xDcx7RcU2QK9PgF4f9cm2ufswetA8g6J4KaOiQDu2iwJfQliY5Xz3kZRANALMvtzmNY7IW5Uh/HjSIwS4xeqADuiADuiADuiA/wXw5Suzfr0x8Kpe/9kV3P4ZdEAHdEAHdEAHdEAH/JvAX7F9yqtIlGwFAAAAAElFTkSuQmCC";
	var kImageAobaBG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAQAAAAAgBAMAAAAPh7vXAAAAMFBMVEUtPUpVaYBjGEqFmqmoucTE09////////8AAAD////////////////////////////HPA3CAAACfklEQVR42u2Vz4qjQBDGlWSgbyY4C958hQnZgDd3SYTcsmEmMDev8xjdGKFuvqohCrn1VlX7b11hTZhlh50UIWrZdv386uvWkm70ZmPMMZYYcGVkuokLXev2lh667odFf1TcwqDjtQC6EzcDuBg3A3j1mbodYIFxM8AfCo4CoN7/vwC9Fg0CbDBwGczc5XLx7gA9kw4CHDD+lgL9ZToI8C/jQwCk23FjBcC0l5qK9wDY5XSmqE3e7zxNHkpIvnpNVYm/+R7HWnZECWm5e9l59KhHwSGAOu9oqDrN5/4QQJ2XJ5A/KMNXcLyAymnR7LR+xUOi4zN+SsyQqwDCbXqmQmjSDKeeO0+/AlR5JBFfKiXAcCr2tS0K06HQOwrCBCWuAXgobTvet4V83e4dXQB80SJ7ZRDOZ95jpPmUsygBd5IA0pwVGecBVbpaP+mgldqfDbbA9YNQklSZaZEjppuTUcQspciaRHggJpJEjQSAAN0kVGs24fMNWW9ejQlD8MWBAK0KACS3IC01cT0UsV5XAKEYr4ApIFqpYx0dt0MeeAGfF43xHDgISVLL+BuEHk7zvOKm1yKNVkDiHlx2CtmHtTwNAGDrQ251gWcuCiHAJoAsl2RIOWMc4gwgRUS1GQkAla0SKhTwDFAMAOCknEbLnSW2wl84LL2y9ZZtkRgvhpML7RFjgwH4+caEEbDX6kiqvD9bszDY33iFi925PCtNL50GxY7AzSqALDYNTEfvA9h2LlSbzf++yrsKUB4LTEDzzI/kN5zb2UbTnJCO+9jsDLrk7eJgnhu/EYHcd6UGFb90RzT5XqTBtDTp6GCOSeTB1fEhvoZ3gDvAHeBzA/wEhgJf9sDwrjoAAAAASUVORK5CYII=";
})(window);

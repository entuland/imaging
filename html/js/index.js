'use strict';

function Palette() {
	var self = this;
	
	self.colors = [];
	
	var cache = {};
	
	self.closest = function(rgb) {
		var key = rgb.join(",");
		if(!cache[key]) {
			var min_distance = 3 * (255 * 255);
			var closest = -1;
			for(var i = 0; i < self.colors.length; ++i) {
				var dist = squaredDist(rgb, self.colors[i]);
				if(dist < min_distance) {
					min_distance = dist;
					closest = i;
				}
			}
			cache[key] = closest;
		}
		return cache[key];
	}
}

function squaredDist(a, b) {
	return Math.pow(a[0] - b[0], 2)  +Math.pow(a[1] - b[1], 2) + Math.pow(a[2] - b[2], 2);
}

function addRGB(a, b) {
	return [
		a[0] + b[0],
		a[1] + b[1],
		a[2] + b[2],
		a[3],
	];
}

function subRGB(a, b) {
	return [
		a[0] - b[0],
		a[1] - b[1],
		a[2] - b[2],
		a[3],
	];
}

function mulRGB(a, b) {
	return [
		a[0] * b[0],
		a[1] * b[1],
		a[2] * b[2],
		a[3],
	];
}

function divRGB(a, b) {
	return [
		a[0] / b[0],
		a[1] / b[1],
		a[2] / b[2],
		a[3],
	];
}


function addN(a, n) {
	return [
		a[0] + n,
		a[1] + n,
		a[2] + n,
		a[3],
	];
}

function subN(a, n) {
	return [
		a[0] - n,
		a[1] - n,
		a[2] - n,
		a[3],
	];
}

function mulN(a, n) {
	return [
		a[0] * n,
		a[1] * n,
		a[2] * n,
		a[3],
	];
}

function divN(a, n) {
	return [
		a[0] / n,
		a[1] / n,
		a[2] / n,
		a[3],
	];
}

function clamp(min, n, max) {
	if(n < min) { return min; }
	if(n > max) { return max; }
	return n;
}

function clampRGB(a) {
	return [
		clamp(0, a[0], 255),
		clamp(0, a[1], 255),
		clamp(0, a[2], 255),
		clamp(0, a[3], 255),
	];
}

function MatrixHelper(canvas) {
	var ctx = canvas.getContext("2d");
	var raw = ctx.getImageData(0, 0, canvas.width, canvas.height);
	var self = this;
	
	self.width = canvas.width;
	self.height = canvas.height;
	
	self.indices = [];
	self.setIndex = function(x, y, index) {
		self.indices[y * self.width + x] = index;
	};
	
	self.getPixel = function(x, y) {
		var index = (y * self.width + x) * 4;
		return [
			raw.data[index],
			raw.data[index+1],
			raw.data[index+2],
			raw.data[index+3],
		];
	};
	
	self.setPixel = function(x, y, pixel) {
		var index = (y * self.width + x) * 4;
		raw.data[index] = pixel[0];
		raw.data[index+1] = pixel[1];
		raw.data[index+2] = pixel[2];
		raw.data[index+3] = pixel[3];
	};
	
	self.update = function() {
		ctx.putImageData(raw, 0, 0);
	};
}

var app = {
	
	init: function() {
		app.imageInput = document.querySelector("#imageInput");
		app.imagePreview = document.querySelector("#imagePreview");
		app.paletteInput = document.querySelector("#paletteInput");
		app.palettePreview = document.querySelector("#palettePreview");
		app.dithering = document.querySelector("#dithering")
		app.minAlpha = document.querySelector("#minAlpha")
		
		app.coverDiv = document.querySelector("#cover");
		app.progressDiv = document.querySelector("#progress");
		
		app.resultPreview = document.querySelector("#resultPreview");
		app.output = document.querySelector("#output");
		app.output.addEventListener("focus", function() {
			app.output.select();
		});
		app.initImageLoader();
		app.initPaletteLoader();
		app.initPaletteButtons();
		app.executeButton = document.querySelector("#execute");
		app.executeButton.addEventListener("click", app.generateOutput);
	},
	
	progress: function(msg) {
		app.progressDiv.innerHTML = msg;
	},
	
	progressXY: function(x, y, matrix) {
		var total = matrix.width * matrix.height;
		var current = y * matrix.width + x;
		var percent = Math.floor(100 / total * current);
		app.progress("Progress: " + percent + "%");
	},
	
	finalize: function(matrix) {
		matrix.update();
		app.resultPreview.style.display = "block";
		app.coverDiv.style.display = "none";
		
		var cells = [];
		cells.push(matrix.width);
		cells.push(matrix.height);
		var curcell = {
			index: false,
			count: 0.
		};
		
		function addCell(cell) {
			if(cell.count) {
				var index = cell.index === false ? "" : cell.index;
				var count = cell.count > 1 ? cell.count : "";
				cells.push(index + ":" + count);
			}
		}
		
		for(var i = 0; i < matrix.indices.length; ++i) {
			var index = matrix.indices[i];
			if(index === curcell.index) {
				curcell.count++;
			} else {
				addCell(curcell);
				curcell = {
					index: index,
					count: 1,
				};
			}
		}
		
		addCell(curcell);
		
		app.output.value = cells.join(" ");
	},
	
	generateOutput: function() {
		if(!app.validPalette()) {
			return;
		}
		if(!app.validImage()) {
			return;
		}
		
		app.coverDiv.style.display = "block";
		var palette = app.extractPalette();
		
		var canvas = app.resultPreview;
		canvas.style.display = "none";
		var ctx = canvas.getContext("2d");
		canvas.height = app.imagePreview.naturalHeight;
		canvas.width = app.imagePreview.naturalWidth;
		ctx.drawImage(app.imagePreview, 0, 0);
		var matrix = new MatrixHelper(canvas);
		
		function process_next_pixel(x, y, callback, batch) {
			app.progressXY(x, y, matrix);
			var iterations = batch;
			while(iterations--) {
				if(x >= matrix.width) {
					x = 0;
					++y;
				}
				if(y >= matrix.height) {
					setTimeout(function() {
						app.finalize(matrix);
					}, 0);
					return;
				}
				callback(x, y, matrix);
				++x;
			}
			setTimeout(function() {
				process_next_pixel(x, y, callback, batch);
			}, 0);
		}
		
		function plainColorCallback(x, y) {
			var px = matrix.getPixel(x, y)
			if(px[3] < app.minAlphaValue) {
				px[0] = px[1] = px[2] = px[3] = 0;
				matrix.setPixel(x, y, px);
				matrix.setIndex(x, y, false);
				return;
			} else {
				px[3] = 255;
			}
			var index = palette.closest(px);
			if(index > -1) {
				px = palette.colors[index];
				matrix.setPixel(x, y, px);
				matrix.setIndex(x, y, index);
			} else {
				matrix.setIndex(x, y, false);
			}
		}
		
		function maybeAdd(x, y, add) {
			if(x < 0 || x >= matrix.width || y >= matrix.height) {
				return;
			}
			var px = matrix.getPixel(x, y);
			px = clampRGB(addRGB(px, add));
			matrix.setPixel(x, y, px);
		}
		
		function ditheredColorCallback(x, y, matrix) {
			var px = matrix.getPixel(x, y);
			if(px[3] < app.minAlphaValue) {
				px[0] = px[1] = px[2] = px[3] = 0;
				matrix.setPixel(x, y, px);
				matrix.setIndex(x, y, false);
				return;
			} else {
				px[3] = 255;
			}
			var index = palette.closest(px);
			if(index > -1) {
				var new_px = palette.colors[index];
				matrix.setPixel(x, y, new_px);
				matrix.setIndex(x, y, index);
				var error = subRGB(px, new_px)
				maybeAdd(x + 1, y    , mulN(error, 7/16));
				maybeAdd(x - 1, y + 1, mulN(error, 3/16));
				maybeAdd(x    , y + 1, mulN(error, 5/16));
				maybeAdd(x + 1, y + 1, mulN(error, 1/16));
			} else {
				matrix.setIndex(x, y, false);
			}
		}
		
		app.minAlphaValue = parseInt(app.minAlpha.value);
		var callback = plainColorCallback;
		if(app.dithering.checked) {
			callback = ditheredColorCallback;
		}
		
		var batch = Math.floor(canvas.height * canvas.width * 0.01)
		if(batch < 1) {
			batch = 1;
		}
		process_next_pixel(0, 0, callback, batch);
	},
	
	extractPalette: function() {
		var canvas = document.createElement("canvas");
		var ctx = canvas.getContext("2d");
		canvas.height = app.palettePreview.naturalHeight;
		canvas.width = app.palettePreview.naturalWidth;
		ctx.drawImage(app.palettePreview, 0, 0);
		var palette = new Palette();
		for(var y = 0; y < canvas.height; ++y) {
			for(var x = 0; x < canvas.width; ++x) {
				var px = ctx.getImageData(x, y, 1, 1);
				palette.colors.push([
					px.data[0],
					px.data[1],
					px.data[2],
					px.data[3],
				])
			}
		}
		return palette;
	},
	
	error: function(after, message) {
		var errors = after.parentNode.querySelectorAll(".error");
		for(var i = 0; i < errors.length; ++i) {
			errors[i].remove();
		}
		if(message) {
			var div = document.createElement("div");
			div.classList.add("error");
			div.innerText = message;
			after.insertAdjacentElement("afterend", div);
		}
	},
	
	validImage: function() {
		if(!app.imagePreview.naturalHeight) {
			app.error(app.imagePreview, "Invalid or missing image")
			return false;
		}
		app.error(app.imagePreview)
		return true;
	},
	
	validPalette: function() {
		if(app.palettePreview.naturalHeight * app.palettePreview.naturalWidth !== 256) {
			app.error(app.palettePreview, "Invalid palette size (pixel count must be 256)")
			return false;
		}
		app.error(app.palettePreview)
		return true;
	},
	
	initImageLoader: function() {
		var imageReader = new FileReader();
		imageReader.addEventListener('load', function () {
			app.imagePreview.src = imageReader.result;
		}, false);
		app.imageInput.addEventListener('change', function() {
			var file = app.imageInput.files[0];
			if(file) {
				imageReader.readAsDataURL(file);
			}
		});				
		app.imagePreview.addEventListener("load", function() {
			app.validImage();
		});
	},
	
	initPaletteLoader: function() {
		var paletteReader = new FileReader();
		paletteReader.addEventListener('load', function () {
			app.palettePreview.src = paletteReader.result;
		}, false);
		app.paletteInput.addEventListener('change', function() {
			var file = app.paletteInput.files[0];
			if(file) {
				paletteReader.readAsDataURL(file);
			}
		});
		app.palettePreview.addEventListener("load", function() {
			app.validPalette();
		});
	},
	
	initPaletteButtons: function() {
		document.querySelector("#loadVGA").addEventListener("click", function() {
			app.palettePreview.src = app.images.palettes.vga;
		});
		document.querySelector("#loadGrayscale").addEventListener("click", function() {
			app.palettePreview.src = app.images.palettes.grayscale;
		});
		document.querySelector("#loadSepia").addEventListener("click", function() {
			app.palettePreview.src = app.images.palettes.sepia;
		});
		app.palettePreview.src = app.images.palettes.vga;
	},
}

window.addEventListener('load', app.init);

# TFLite Micro smoke test: runs the tflite-micro hello_world model (y = sin(x)).
# Upload hello_world_float.tflite and this file to the board's file system, then
# run `br load("/sine_test.be")` from the console. Results go to the log.
import TFL
import math

var xs = [0, 0.5, 1, 1.57, 2.5, 3.14, 4, 4.71, 5.5, 6]
var inp = bytes(-4)
var out = bytes(-4)
var idx = 0

TFL.begin("BUF")
var f = open("/hello_world_float.tflite")
var model = f.readbytes()
f.close()
model.resize((size(model) + 7) / 8 * 8)  # TFL.load wants a multiple of 8 bytes
TFL.load(model, out, 3000)

def step()
  if idx > 0
    if !TFL.output(out)   # inference runs in its own task; poll until done
      tasmota.set_timer(50, step)
      return
    end
    var x = xs[idx - 1]
    print(format("TFL x=%.2f model=%.3f sin=%.3f", x, out.getfloat(0), math.sin(x)))
  end
  if idx < size(xs)
    inp.setfloat(0, xs[idx])
    TFL.input(inp)
    idx += 1
    tasmota.set_timer(100, step)
  else
    print("TFL stats " + str(TFL.stats()))
  end
end

tasmota.set_timer(500, step)

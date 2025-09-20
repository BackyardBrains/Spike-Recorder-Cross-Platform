import 'dart:typed_data';
import 'dart:math' as math;

class CircularFloatArrayBuffer {
  List<Float32List> buffer = [];
  int wCapacity = 8192;
  int hCapacity = 8192;

  int available = 0;
  int idxGet = 0;
  int idxPut = 0;

  CircularFloatArrayBuffer(this.wCapacity , int hCapacity) {
    buffer = List<Float32List>.generate(wCapacity, (idx) => Float32List(hCapacity));
  }
      

  /// Clears all data from the buffer.
  void clear() {
    idxGet = idxPut = available = 0;
  }

  /// Gets as many of the requested float arrays as available from this buffer.
  int get(List<Float32List> dst) {
    return _get(dst, 0, dst.length);
  }

  /// Gets as many of the requested float arrays as available from this buffer.
  int _get(List<Float32List> dst, int off, int len) {
    if (available == 0) return 0;

    final limit = idxGet < idxPut ? idxPut : wCapacity;
    int count = math.min(limit - idxGet, len);
    // print("COPY GET");
    _copy(buffer, idxGet, dst, off, count);
    idxGet += count;

    if (idxGet == wCapacity) {
      int count2 = math.min(len - count, idxPut);
      if (count2 > 0) {
        _copy(buffer, 0, dst, off + count, count2);
        idxGet = count2;
        count += count2;
      } else {
        idxGet = 0;
      }
    }
    // print("AVAILABLE: $available ---- $count");
    available -= count;
    return count;
  }

  /// Puts as many of the given float arrays as possible into this buffer.
  int put(List<Float32List> src, int off, int wLen) {
    if (available == wCapacity) return 0;
    final limit = idxPut < idxGet ? idxGet : wCapacity;
    int count = math.min(limit - idxPut, wLen);
    _copy(src, off, buffer, idxPut, count);
    idxPut += count;
    // print("Available: $off $available, $wCapacity || $wLen == $count");

    if (idxPut == wCapacity) {
      int count2 = math.min(wLen - count, idxGet);
      if (count2 > 0) {
        try{
          _copy(src, off + count, buffer, 0, count2);
        } catch(e){
          print("ERROR COPY: $e");
        } 
        idxPut = count2;
        count += count2;
      } else {
        idxPut = 0;
      }

    }
    available += count;
    // print("fftBuffer.put result: $count");        

    return count;
  }

  void _copy(List<Float32List> src, int srcPos, List<Float32List> dst, int dstPos, int wLength) {
    int dstCounter = 0;
    for (int i = srcPos; i < srcPos + wLength; i++) {
      dst[dstPos + dstCounter].setAll(0, src[i].sublist(0, math.min(src[i].length, dst[dstPos + dstCounter].length)) );
        // System.arraycopy(src[i], 0, dst[dstPos + dstCounter], 0,
        //     Math.min(src[i].length, dst[dstPos + dstCounter].length));
      dstCounter++;
    }    
    // print("LENGTH ARR BUFFER: SRCPOS: $srcPos , DSTPOS : $dstPos Wlength: Wlength--- ${src[0].sublist(0, math.min(src[0].length, dst[dstPos + dstCounter].length))}");
    // for (int i = 0; i < wLength; i++) {
    //   final int srcIndex = srcPos + i;
    //   final int dstIndex = dstPos + i;
    //   final int lengthToCopy = math.min(src[srcIndex].length, dst[dstIndex].length);
    //   dst[dstIndex].setRange(0, lengthToCopy, src[srcIndex]);
    // }
  }
}
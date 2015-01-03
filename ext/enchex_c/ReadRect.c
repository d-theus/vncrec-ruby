#include <ruby.h>
#include <ruby/io.h>
#include <fcntl.h>

#include <math.h>

int my_readbyte(VALUE io){
  return NUM2INT( rb_funcall(io, rb_intern("readbyte"),0));
}

char *my_read(VALUE io, long nbytes){
  char * result = (char*)malloc(nbytes+1);
  VALUE nbytes_v = INT2NUM(nbytes);
  VALUE rstr = rb_funcall(io, rb_intern("read"), 1,nbytes_v);
  memcpy(
      result,
      RSTRING_PTR(rstr),
      RSTRING_LEN(rstr)
      );
  return result;
}

VALUE mVNC = Qnil;
VALUE mEncHextile = Qnil;
VALUE mRFB = Qnil;

void Init_enchex_c();

static VALUE read_rect_c(VALUE self,VALUE io, VALUE _x, VALUE _y, VALUE _w, VALUE _h, VALUE bitspp, VALUE fb, VALUE fbw, VALUE fbh);

void Init_enchex_c() {
  mVNC = rb_define_module("VNCRec");
  mRFB = rb_define_module_under(mVNC, "RFB");
  mEncHextile = rb_define_module_under(mRFB, "EncHextile");
  rb_define_module_function(mEncHextile, "read_rect", read_rect_c, 9);
}

void _read_subrect_c(int rx, int ry, int rw, int rh, int tx, int ty, char *fg, VALUE io, char* fb, int fbw, int fbh, int bpp){

  unsigned char xy, wh;
  xy = my_readbyte(io);
  wh = my_readbyte(io);

  if(!fb)
    return;

  unsigned char stx = (xy & 0xF0) >> 4;
  unsigned char stw = ((wh & 0xF0) >> 4) + 1;
  unsigned char sty = (xy & 0x0F);
  unsigned char sth = (wh & 0x0F) + 1;
  rw *= bpp;
  rx *= bpp;
  tx *= bpp;
  stx *= bpp;
  stw *= bpp;
  char *fg_row = (char*)malloc(stw);
  int k,l;
  for(k = 0; k < stw; k+=bpp){
    for(l = 0; l < bpp; l++){
      fg_row[k+l] = fg[l];
    }
  }

  int i;
  for (i = 0; i < sth; i++) {
    register int row_begin = fbw*(ry+ty+sty+i) + rx + tx + stx;
    memcpy(&fb[row_begin], fg_row, stw);
  }
  free(fg_row);
}

void _read_subrect_c_raw(int rx, int ry, int rw, int rh, int tx, int ty, int tw, int th, VALUE io, char* fb, int fbw, int fbh, int bpp){

  rw *= bpp;
  rx *= bpp;
  tw *= bpp;
  tx *= bpp;

  int trow;
  char *data = my_read(io, tw*th);

  if(!fb){
    return;
  }

  for (trow = 0; trow < th; trow++) {
    register int row_begin = fbw*(ry+ty+trow) + rx + tx;
    memcpy( &fb[row_begin], &data[trow*tw],tw);
  }
  free(data);
}

void _fill_tile_bg(int rx, int ry, int rw, int rh, int tx, int ty, int tw, int th, char*bg, VALUE io, char* fb, int fbw, int fbh, int bpp){
  if(!fb)
    return;

  rw *= bpp;
  rx *= bpp;
  tw *=bpp;
  tx *= bpp;
  int trow;
  char *bg_row = (char*)malloc(tw);
  int k,l;
  for(k = 0; k < tw; k+=bpp){
    for(l = 0; l < bpp; l++){
      bg_row[k+l] = bg[l];
    }
  }
  register int base_row_begin = fbw*(ry+ty) + rx + tx;
  for (trow = 0; trow < th; trow++) {
    register int row_begin = base_row_begin + fbw*trow;
    memcpy(&fb[row_begin], bg_row, tw);
  }
  free(bg_row);
}

static VALUE read_rect_c(VALUE self,VALUE io, VALUE _x, VALUE _y, VALUE _w, VALUE _h, VALUE bitspp, VALUE _fb, VALUE _fbw, VALUE _fbh){
  int w = NUM2INT(_w);
  int h = NUM2INT(_h);
  int rx = NUM2INT(_x);
  int ry = NUM2INT(_y);
  int fbw = NUM2INT(_fbw);
  int fbh = NUM2INT(_fbh);
  int bpp = (float)NUM2INT(bitspp) / 8.0;


  int tiles_row_num = ceil((float)h/16.0);
  int tiles_col_num = ceil((float)w/16.0);

  char *fb;
  int fbsize = fbw*fbh;
  if(ry > fbh || rx * bpp > fbw)
    fb = NULL; // skip
  else
    fb = (char*)malloc(fbsize);
  if(fb)
    memcpy(fb,RSTRING(_fb)->as.heap.ptr,RSTRING(_fb)->as.heap.len);

  int last_tile_w = w % 16;
  int last_tile_h = h % 16;

  char prev_tile_bg[4];
  char prev_tile_fg[4];

  int i,j;
  int tw, th;
  int ty, tx;
  int ti,tj,tk;
  unsigned char subenc;
  for (i = 0; i < tiles_row_num; i++) {

    if ((i == tiles_row_num-1) && (last_tile_h > 0))
      th = last_tile_h;
    else
      th = 16;
    ty = 16 * i;
    for (j = 0; j < tiles_col_num; j++) {
      
      if ((j == tiles_col_num-1) && (last_tile_w > 0))
        tw = last_tile_w;
      else
        tw = 16;
      tx = 16 * j;

      subenc = my_readbyte(io);

      if(subenc & 1){ //raw
        _read_subrect_c_raw(rx,ry,w,h,tx,ty,tw,th,io,fb,fbw,fbh,bpp);
      }
      if(subenc & 2){//background specified
        for (tk = 0; tk < bpp; tk++) {
          prev_tile_bg[tk] = my_readbyte(io);
        }
      }
      if(!(subenc & 1)){//should not refill raw
        for (ti = 0; ti < th; ti++) {
          for(tj = 0; tj < tw; tj++){
            _fill_tile_bg(rx,ry,w,h,tx,ty,tw,th,prev_tile_bg,io,fb,fbw,fbh,bpp);
          }
        }
      }
      if(subenc & 4){//foreground specified
        for (tk = 0; tk < bpp; tk++) {
          prev_tile_fg[tk] = my_readbyte(io);
        }
      }
      if(subenc & 8){//any subrect
        size_t subrects_number = my_readbyte(io);
        size_t subrect;
        char fg[4];
        for (subrect = 0; subrect < subrects_number; subrect++) {
          if(subenc & 16){//subrect colored
            for (tk = 0; tk < bpp; tk++) {
              fg[tk] = my_readbyte(io);
            }
            _read_subrect_c(rx,ry,w,h,tx,ty, fg, io, fb, fbw, fbh, bpp);
          }else{
            _read_subrect_c(rx,ry,w,h,tx,ty, prev_tile_fg, io, fb, fbw, fbh, bpp);
          }
        }
      }

    } //for j
  }//for i

  if(fb) {
    for (i = 0; i < fbh; i++) {
      rb_str_update(_fb, i*fbw, fbw,
          rb_str_new(&fb[i * fbw], fbw));
    }
    free(fb);
  }

  return Qtrue;
}

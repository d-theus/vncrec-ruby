require "vncrec"


describe VNCRec::Writers do

  describe ".get_writer" do
    after(:all) {|| `rm -f *.raw *.mp4`}
    after(:each) {|| begin $w.close; rescue NoMethodError; end; $w = nil}
    it "handles no extension correctly" do
      $w = VNCRec::Writers.get_writer("somefile", geometry: "1920x1080",pix_fmt: "bgr8")
      expect($w).to be_kind_of(VNCRec::Writers::RawVideo)
      field = $w.instance_variable_get(:@filename)
      fn = File.basename(field)
      expect(fn).to eq("somefile.raw")
    end
    it "handles raw extension correctly" do
      $w = VNCRec::Writers.get_writer("somefile.raw", geometry: "1920x1080",pix_fmt: "bgr8")
      expect($w).to be_kind_of(VNCRec::Writers::RawVideo)
      field = $w.instance_variable_get(:@filename)
      fn = File.basename(field)
      expect(fn).to eq("somefile.raw")
    end
    it "handles mp4 extension correctly" do
      $w = VNCRec::Writers.get_writer("somefile.mp4", geometry: "1920x1080",pix_fmt: "bgr8")
      expect($w).to be_kind_of(VNCRec::Writers::FFmpeg)
      field = $w.instance_variable_get(:@filename)
      fn = File.basename(field)
      expect(fn).to eq("somefile.mp4")
    end
    it "handles /dev/null correctly" do
      $w = VNCRec::Writers.get_writer("somefile.mp4", geometry: "1920x1080",pix_fmt: "bgr8")
      expect($w).to be_kind_of(VNCRec::Writers::FFmpeg)
      field = $w.instance_variable_get(:@filename)
      fn = File.basename(field)
      expect(fn).to eq("somefile.mp4")
    end
    context "when file cannot be created" do
      it "raises error" do
        expect do
          VNCRec::Writers.get_writer("/root/somefile")
        end.to raise_error "Cannot create output file"
      end
    end
  end

  describe VNCRec::Writers::RawVideo do
    after(:each) {|| begin subject.close(); rescue IOError; end; `rm -f *.raw`}
    subject {VNCRec::Writers::RawVideo.new("file.raw")}
    it "initializes" do
      subject.inspect
    end
    it "closes correctly" do
      expect do
        subject.inspect
        subject.close
      end.not_to raise_error
    end
    it "#write" do
      expect(subject).to respond_to(:write)
      subject.inspect
      filesize = File.size("file.raw")
      expect do 
        subject.write("\xFF"*10e+6)
        filesize = File.size("file.raw")
      end.to change{filesize}.from(0).to(10e+6)
    end
  end
  
  describe VNCRec::Writers::FFmpeg do

    context "initialization" do
    after(:all) { `rm -f *.mp4`}
      it "Raises exception in case of wrong args" do
        expect { || VNCRec::Writers::FFmpeg.new}.to raise_error(ArgumentError)
        expect { || VNCRec::Writers::FFmpeg.new("somefile.mp4", pix_fmt: "bgr8")}.to raise_error("Undefined frame size")
        expect { || VNCRec::Writers::FFmpeg.new("somefile.mp4", geometry: "1920x1080")}
        expect {VNCRec::Writers::FFmpeg.new("somefile.mp4", geometry: "1920x1080")}.to raise_error("Undefined pixel format")
      end
      it "Raises nothing given correct args" do
        expect { || VNCRec::Writers::FFmpeg.new("somefile.mp4", geometry: "1920x1080",pix_fmt: "bgr8").close}.not_to raise_error
      end
      context "when passed pixel format" do
        subject {VNCRec::Writers::FFmpeg.new("somefile.mp4", geometry: "1920x1080", pix_fmt: "bgra")}
        after(:each) {subject.close; `killall ffmpeg`}
        it "sets @pix_fmt correspondingly" do
          expect(subject.instance_variable_get(:@pix_fmt)).to eq VNCRec::PIX_FMT_BGRA
          expect(subject.instance_variable_get(:@cmd)).to include("-pix_fmt bgra")
        end
      end
    end

    context "Closing:" do
      w = VNCRec::Writers::FFmpeg.new("somefile.mp4", geometry: "1920x1080",pix_fmt: "bgr8")
      w.close
      it "#close closes" do 
        expect(w.closed?).to be_truthy
      end
      it "double #close raises" do
        expect do
          w.close
        end.to raise_error
      end
    end

    describe "Writing" do
      subject {|| VNCRec::Writers::FFmpeg.new("somefile.mp4", geometry: "300x300",pix_fmt: "bgr8") }
      after(:each) {|| begin; subject.close; rescue ;end }
      context "when closed" do
        it "raises error" do
          subject.close
          expect{ || subject.write("somedata") }.to raise_error("No writer running")
        end
      end
      it "creates exactly one file w/ exact name" do
        subject.write("\x00"*(300*300*3))
        expect(File.exists?("somefile.mp4")).to be_truthy
      end
    end
  end

end

require 'spec_helper.rb'
Rec = VNCRec::Recorder

describe Rec do
  describe '#intialize' do
    let(:width) { r.instance_variable_get(:@w) }
    let(:height) { r.instance_variable_get(:@h) }

    describe 'option geometry:' do
      context 'passed with wrong format' do
        it 'leads to fail' do
          expect { Rec.new(geometry: '1920') }.to raise_error ArgumentError
          expect { Rec.new(geometry: 1920) }.to raise_error ArgumentError
        end
      end

      context 'passed and correct' do
        let(:r) { Rec.new(geometry: '800x600') }

        it 'raises no error' do
          expect { r }.not_to raise_error
        end

        it 'IVs are set' do
          r
          r.send(:parse_geometry)
          expect(width).to eq(800)
          expect(height).to eq(600)
        end
      end
    end

    context 'encoding' do
      let(:iv) { rec.instance_variable_get(:@enc) }

      context 'given raw' do
        let(:rec) { Rec.new(encoding: VNCRec::ENC_RAW) }

        it ' sets iv to constant ENC_RAW' do
          rec
          expect(iv).to eq VNCRec::ENC_RAW
        end
      end

      context 'given zrle' do
        let(:rec) { Rec.new(encoding: VNCRec::ENC_ZRLE) }

        it ' sets iv to constant ENC_ZRLE' do
          rec
          expect(iv).to eq VNCRec::ENC_ZRLE
        end
      end

      context 'given hextile' do
        let(:rec) { Rec.new(encoding: VNCRec::ENC_HEXTILE) }

        it ' sets iv to constant ENC_HEXTILE' do
          rec
          expect(iv).to eq VNCRec::ENC_HEXTILE
        end
      end
    end

    describe 'option host:', port: true do
      context 'when given' do
        before do
          @sock = nil
          Thread.new do
            @sock = TCPServer.new(5900).accept
          end.run
        end

        let(:rec) { Rec.new host: 'localhost', port: 5900 }

        it 'rec tries to connect' do
          expect do
            rec.run
            sleep 1
          end.to change { @sock.nil? }
          .from(true).to(false)
        end
      end
      context 'when not given' do
        let(:rec) { Rec.new }

        it 'rec listens on specified port' do
          rec.run
          sleep 1
          expect(pid_using_port 5900).to eq Process.pid
        end
      end
    end

    describe 'option pixel format:' do
      subject { rec.instance_variable_get(:@pix_fmt) }
      context 'passing bgra' do
        let(:rec) { Rec.new(filename: 'file.mp4', pix_fmt: 'bgra') }

        it 'does not raise error' do
          expect { rec }.not_to raise_error
        end
        it { is_expected.to eq VNCRec::PIX_FMT_BGRA }
      end

      context 'passing bgr8' do
        let(:rec) { Rec.new(filename: 'file.mp4', pix_fmt: 'bgr8') }

        it 'does not raise error' do
          expect { rec }.not_to raise_error
        end
        it { is_expected.to eq VNCRec::PIX_FMT_BGR8 }
      end

      context 'passing other' do
        let(:rec) { Rec.new(filename: 'file.mp4', pix_fmt: 'gbr32') }

        it 'raises error' do
          expect { rec }.to raise_error ArgumentError
        end
      end
    end

    describe 'option port:', port: true do
      let(:rec) { Rec.new(port: port) }
      context 'valid integer given' do
        let(:port) { 5900 }

        it 'does not raise error' do
          expect { rec }.not_to raise_error
        end
      end
      context 'integer too big' do
        let(:port) { 10_000_000 }
        it 'raises ArgumentError' do
          expect { rec }.to raise_error ArgumentError
        end
      end
      context 'integer too small' do
        let(:port) { 0 }
        it 'raises ArgumentError' do
          expect { rec }.to raise_error ArgumentError
        end
      end
      context 'non-integer' do
        let(:port) { 'aa' }
        it 'raises ArgumentError' do
          expect { rec }.to raise_error ArgumentError
        end
      end
    end

    describe 'option filename:' do
      let(:f1) { Rec.new }
      let(:f2) { Rec.new(filename: 'file') }
      let(:f3) { Rec.new(filename: '/root/file') }
      let(:f4) { Rec.new(filename: 'rec_1_DATE.mp4').run; }

      context 'when no filename given' do
        it 'file with default name exists' do
          expect { f1 }.to change { File.exist?('5900.raw') }.from(false).to(true)
        end
      end
      context 'when given' do
        it 'file with specified name exists' do
          expect { f2 }.to change { File.exist?('file') }.from(false).to(true)
        end
      end
      context 'when can create file' do
        it 'file exists' do
          expect { f2 }.to change { File.exist?('file') }.from(false).to(true)
        end
      end
      context 'when can not create file' do
        it 'raises error' do
          expect { f3 }.to raise_error(/Cannot create file .*/)
        end
      end
      context 'when template DATE is given' do
        fit 'file with template substitute as name exist', port: true do
          f4
          launch_vnc_server 5900
          expect do
            sleep 3
            `killall -KILL x11vnc`
            sleep 0.5
            puts Dir.glob('*')
          end.to change { Dir.glob('rec_1_*_*_*_*h_*m_*s.mp4').grep(/_\d\dh_/).size }.from(0).to(1)
        end
      end
    end
  end
  describe 'filesize do', port: true do
    let(:rec) { Rec.new(filename: 'somefile.mp4') }
    context 'when running' do
      it 'returns > 0' do
        rec.run
        launch_vnc_server 5900
        sleep 3.5
        expect(rec.filesize).to be > 0
      end
    end

    context 'when not yet running' do
      it 'returns 0' do
        rec.run
        sleep 0.5
        expect(rec.filesize).to eq(0)
      end
    end
  end
  describe '#running?', port: true, vnc: true do
    let(:rec) { Rec.new(filename: '/dev/null') }
    context 'when not yet connected' do
      it 'returns false' do
        expect(rec.running?).to be_falsy
      end
    end

    context 'when connected' do
      before { rec.run }
      it 'returns true' do
        launch_vnc_server 5900
        expect(rec.running?).to be_truthy
      end
    end
  end
  describe 'network issues', port: true, vnc: true do
    subject(:rec)  { Rec.new(filename: 'file.raw', port: get_free_port) }
    subject(:port) { rec.instance_variable_get(:@port) }
    context 'when server is not responding' do
      it 'exits eventually, correct close' do
      end
    end
    context 'when connection is lost' do
      after(:each) do
        `killall x11vnc &>/dev/null`
      end
      it 'closes correctly', port: true do
        rec.run
        launch_vnc_server port
        sleep 4
        `killall x11vnc &>/dev/null`
        sleep 1
        expect(rec.stopped?).to be_truthy
      end
    end
  end
  describe 'basic functionality' do
    describe 'Pix format', port: true, vnc: true do
      before(:each) { `rm -f rec.jpg &>/dev/null` }
      let(:port) { get_free_port }
      let(:geo) { '800x600' }
      let(:common_options) do
        {
          geometry: geo,
          filename: 'file.raw',
          encoding: VNCRec::ENC_RAW,
          port:     port
        }
      end
      let(:rec) do
        Rec.new(common_options.merge(pix_fmt: f))
      end
      let(:run) do
        rec.run
        sleep 5
        rec.stop
      end

      context 'given bgr8' do
        let(:f) { 'bgr8' }

        it 'produces output' do
          rec
          launch_vnc_server port
          run
          sleep 1
          `ffmpeg -y -f rawvideo  -s #{geo} -r 3 -pix_fmt #{f} -i file.raw \
          -frames 1 rec.jpg &>/dev/null`
          sleep 4
          expect(File.exist?('rec.jpg')).to be_truthy
        end

        context 'given bgra' do
          let(:f) { 'bgra' }

          it 'produces output' do
            rec
            launch_vnc_server port
            run
            sleep 1
            `ffmpeg -y -f rawvideo  -s #{geo} -r 3 -pix_fmt #{f} -i file.raw \
          -frames 1 rec.jpg &>/dev/null`
            sleep 4
            expect(File.exist?('rec.jpg')).to be_truthy
          end
        end
      end
    end

    describe 'Transmission mode', port: true, vnc: true do
      context '(with resolution 800x600)' do
        let(:geo)  { '800x600' }
        describe 'raw' do
          let(:mode) { VNCRec::ENC_RAW }
          let(:port) { get_free_port }
          let(:rec) do
            Rec.new(
              geometry: geo,
              filename: 'file.raw',
              encoding: mode,
              port:     port
            )
          end

          it 'works' do
            rec.run
            launch_vnc_server port
            sleep 3
            rec.stop
            sleep 1
            expect(File.exist?('file.raw')).to be_truthy
            expect(File.size('file.raw')).to be > 0
          end
        end

        describe 'hextile', skip: 1 do
          let(:mode) { VNCRec::ENC_HEXTILE }
          let(:port) { get_free_port }
          let(:rec) do
            Rec.new(
              geometry: geo,
              filename: 'file.raw',
              encoding: mode,
              port:     port
            )
          end

          it 'works' do
            rec.run
            launch_vnc_server port
            sleep 3
            rec.stop
            sleep 1
            expect(File.exist?('file.raw')).to be_truthy
            expect(File.size('file.raw')).to be > 0
          end
        end
      end
    end
    describe '#kill', port: true, vnc: true do
      subject(:rec) { Rec.new(filename: 'file.mp4', port: get_free_port) }
      subject(:port) { rec.instance_variable_get(:@port) }
      before(:each) do
        rec.run
        launch_vnc_server port
        sleep 6
      end
      it 'recorder is dead' do
        ffmpeg = rec.instance_variable_get(:@file)
        expect(rec.stopped?).to be_falsy
        expect(ffmpeg.closed?).to be_falsy
        rec.stop
        sleep 0.5
        expect(rec.stopped?).to be_truthy
        expect(ffmpeg.closed?).to be_truthy
      end
    end
  end
end

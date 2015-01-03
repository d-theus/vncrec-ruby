require 'spec_helper.rb'

describe 'vncrec' do
  describe 'command line options' do
  end

  describe 'sending signals', vnc: true, port: true do
    let(:ps) { `ps -A`.lines.grep(@pid.to_s) }

    before do
      @pid = fork do
        exec 'vncrec'
      end
      sleep 1
    end

    context 'when connected' do
      before { launch_vnc_server 5500 }

      it 'INT stops' do
        expect_no_timeout(3) do
          Process.kill('INT', @pid)
          Process.waitpid(@pid)
        end
        expect($?.exited?).to be_truthy
      end
    end

    context 'when disconnected' do

      it 'INT stops' do
        expect_no_timeout(3) do
          Process.kill('INT', @pid)
          Process.waitpid(@pid)
        end
        expect($?.exited?).to be_truthy
      end
    end
  end
end

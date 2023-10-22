import { connected } from 'process'
import './Login.css'
import Wallet from "./Wallet"
import { WalletKitProvider, useWalletKit } from '@mysten/wallet-kit'

export default function LoginDisplay(){
    const { wallet, connect } = useWalletKit();
    

    const click_handler = () => {
        
        window.location.href = '/main'
        
    }

    return(
        <body>
        <div className="logo_box">
        <div className="sui">Powered by Sui
            <img className="sui_logo" src="/Sui_Droplet_Logo_Blue-3.png"/> 
        </div>
        <div className="wallet"><Wallet></Wallet></div>

        <div className="img_align">
            <img src="/logo_no_text.png" className="logo"/>

            <h2 className="phrase">Simple contracts for blockchain technology.</h2>
        </div>

        <div className="button_align">
            <button type="submit" className="get_started" onClick={click_handler} disabled={!connect}>Get Started</button>
        </div>
    </div>

</body>
    );
}
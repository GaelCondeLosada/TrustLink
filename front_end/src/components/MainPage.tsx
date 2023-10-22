import './MainPage.css'
import Wallet from "./Wallet"
import NewContractDisplay from './NewContract';
import SendNCDTransaction from './SendNCDTransaction';

export default function MainPageDisplay() {


    const w3_open = () => {
        let up_bar = document.getElementById("main_upper_bar");
        if (up_bar != null){
            up_bar.style.marginLeft = "25%";
        } 
        let side_bar = document.getElementById("mySidebar");
        if (side_bar != null){
            side_bar.style.width = "25%";
            side_bar.style.display = "block";
        }
    }

    const w3_close = () => {
        let up_bar = document.getElementById("main_upper_bar");
        if (up_bar != null) { up_bar.style.marginLeft = "0%";}

        let side_bar = document.getElementById("mySidebar");
        if (side_bar != null) { side_bar.style.display = "none";}
    }

    return (
    
        
    <body> 
        <meta name="viewport" content="width=device-width, initial-scale=1"></meta>
        <link rel="stylesheet" href="https://www.w3schools.com/w3css/4/w3.css"></link>
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.2.0/css/all.min.css"></link>      
        <div className="envelope">
        <div className="sidebar w3-bar-block w3-card w3-animate-left" style={ {display: 'none'} }  id="mySidebar">
          <button className="w3-bar-item w3-button w3-large" onClick={w3_close}
          >Close &times;</button>
          <a href="#" className="w3-bar-item w3-button">Link 1</a>
          <a href="#" className="w3-bar-item w3-button">Link 2</a>
          <a href="#" className="w3-bar-item w3-button">Link 3</a>
        </div>

    <div id="main_upper_bar">

        <div className="w3" id="main_text">
            <button id="openNav" className="w3-button w3 w3-xlarge" onClick={w3_open}>&#9776;</button>
            Trustlink
            <img src="/logo_no_text.png" alt="loading"  className="trustlinks_pic"/>
            <div className="wallet"><Wallet></Wallet></div>
            
        </div>

    </div>
        <div className="main_btn">
        <SendNCDTransaction></SendNCDTransaction>

        </div>

        <div className="contracts">
            
        </div>  

    </div>
    </body>
    );
}
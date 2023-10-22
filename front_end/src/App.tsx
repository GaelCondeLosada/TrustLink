import { useState } from 'react'
import './App.css'
import { WalletKitProvider } from '@mysten/wallet-kit'
import MainPageDisplay from './components/MainPage'
import NewContractDisplay from './components/NewContract'
import { BrowserRouter, Routes, Route } from "react-router-dom";
import LoginDisplay from './components/Login'
import NewActionDisplay from './components/Actions'



function App() {
  const [count, setCount] = useState(0)    

  

 
  

  return (
  
    <WalletKitProvider>
    <BrowserRouter>
      <Routes>
          <Route index element={<LoginDisplay />} />
          <Route path="/main" element={<MainPageDisplay/>}/>
          <Route path="/new_contract" element={<NewContractDisplay />} />
          <Route path="/actions" element={<NewActionDisplay />} />

      </Routes>
    </BrowserRouter>
    </WalletKitProvider>

    //<>
    //<WalletKitProvider>
    //  <div>
//
    //    
    //    
    //    <RequirementsDisplay></RequirementsDisplay>
    //    </div>
    //  </WalletKitProvider>
    //</>
  )
}

export default App

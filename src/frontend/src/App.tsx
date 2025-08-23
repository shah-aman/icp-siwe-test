import Header from "./components/header/Header";
import TokenManager from "./components/TokenManager";
import GitHubIcon from "./components/GitHubIcon";
import TokenApproval from "./components/TokenApproval";
import CreateMinerForm from "./components/mining/CreateMinerForm";
import { Toaster } from "react-hot-toast";

function App() {
  return (
    <div className="flex flex-col items-center w-full min-h-screen">
      <Header />
      <main className="flex flex-col items-center flex-grow w-full max-w-2xl gap-12 px-5 pt-12 pb-24">
        {/* The AuthGuard in main.tsx ensures these components only render when logged in */}
        <div className="flex flex-col items-center justify-center flex-grow gap-8">
          <TokenApproval />
          <TokenManager />
          <CreateMinerForm />
        </div>
        <Toaster />
      </main>
      <footer className="w-full py-6">
        <GitHubIcon />
      </footer>
    </div>
  );
}

export default App;

import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import WmtsClientApp from "./WmtsClientApp";
import "./app.css";

const params = new URLSearchParams(window.location.search);
const RootComponent = params.get("mode") === "wmts" ? WmtsClientApp : App;

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <RootComponent />
  </React.StrictMode>
);

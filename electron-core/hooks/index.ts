import { useEffect } from "react";

export function useTheme() {
  useEffect(() => {
    document.documentElement.classList.add("dark");
  }, []);
  return "dark";
}

export function useConnection() {
  return { data: { connected: true }, error: null, isLoading: false };
}

export function useEnvironment() {
  return { data: { available: true, mode: "production" }, error: null, isLoading: false };
}

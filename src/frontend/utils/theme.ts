import { createTheme }from "@mui/material/styles";

export const theme = createTheme({
    cssVariables: true,
    palette: {
        mode: "dark",
        background: {
            default: "#141414"
        }
    },
    typography: {
        fontFamily: "JetBrains Mono Variable, monospace",
    }
})
import Typography from "@mui/material/Typography"

export const DotRowSeparator: React.FC<{ sx?: React.CSSProperties }> = ({ sx }) => {
    return (
        <Typography variant="h6" fontWeight={900} color="var(--mui-palette-text-secondary)"
        sx={{ paddingLeft: "8px", paddingRight: "8px", ...sx }}>•</Typography>
    )
}
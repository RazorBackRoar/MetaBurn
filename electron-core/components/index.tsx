import * as React from "react";
import { createContext, useContext, useId, useState } from "react";
import { cn } from "../utils";

// ─────────────────────────────────────────────────────────────────────────────
// General layout / providers
// ─────────────────────────────────────────────────────────────────────────────

export function TooltipProvider({ children }: { children?: React.ReactNode }) {
  return <>{children}</>;
}

export function Toaster() {
  return null;
}

export function Status({
  variant,
  className,
  children,
}: {
  variant?: "neutral" | "loading" | "success" | "error";
  className?: string;
  children?: React.ReactNode;
}) {
  const color =
    variant === "success"
      ? "text-green-400"
      : variant === "error"
        ? "text-red-400"
        : variant === "loading"
          ? "text-accent"
          : "text-neutral-300";
  return <span className={cn("inline-flex items-center gap-1.5 text-sm", color, className)}>{children}</span>;
}

export function ErrorBoundaryView({
  error,
  className,
}: {
  error?: { message?: string };
  className?: string;
}) {
  return (
    <div className={cn("p-4 text-red-400", className)}>
      <h2 className="font-semibold">Something went wrong</h2>
      <pre className="text-sm">{error?.message || String(error)}</pre>
    </div>
  );
}

export function SplitView({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <div className={cn("flex h-full w-full", className)}>{children}</div>;
}

// ─────────────────────────────────────────────────────────────────────────────
// ScrollArea
// ─────────────────────────────────────────────────────────────────────────────

export function ScrollArea({
  className,
  children,
  toolbar,
  scrollbars,
}: {
  className?: string;
  children?: React.ReactNode;
  toolbar?: React.ReactNode;
  scrollbars?: "vertical" | "horizontal" | "both";
}) {
  const overflow =
    scrollbars === "vertical"
      ? "overflow-y-auto"
      : scrollbars === "horizontal"
        ? "overflow-x-auto"
        : scrollbars === "both"
          ? "overflow-auto"
          : "overflow-auto";
  return (
    <div className={cn("h-full flex flex-col", className)}>
      {toolbar && <div className="shrink-0">{toolbar}</div>}
      <div className={cn("flex-1 min-h-0", overflow)}>{children}</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Toolbar
// ─────────────────────────────────────────────────────────────────────────────

export function Toolbar({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <div className={cn("flex items-center gap-2 p-2", className)}>{children}</div>;
}

export function ToolbarRow({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <div className={cn("flex w-full items-center gap-2", className)}>{children}</div>;
}

export function ToolbarContent({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <div className={cn("flex-1", className)}>{children}</div>;
}

export function ToolbarActions({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <div className={cn("flex items-center gap-2", className)}>{children}</div>;
}

export function ToolbarBackButton({
  label,
  onClick,
  className,
  children,
  ...props
}: {
  label?: string;
  onClick?: () => void;
  className?: string;
  children?: React.ReactNode;
} & React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn("text-sm text-accent hover:underline", className)}
      {...props}
    >
      {children || label || "← Back"}
    </button>
  );
}

export function ToolbarTitle({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <h1 className={cn("text-base font-semibold", className)}>{children}</h1>;
}

// ─────────────────────────────────────────────────────────────────────────────
// Button
// ─────────────────────────────────────────────────────────────────────────────

export function Button({
  variant,
  size,
  asChild,
  className,
  children,
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "accent" | "filled" | "transparent";
  size?: "small" | "medium" | "large";
  asChild?: boolean;
}) {
  const variantClass =
    variant === "accent"
      ? "bg-accent text-black hover:bg-accent-hover"
      : variant === "transparent"
        ? "bg-transparent text-primary hover:bg-white/5"
        : "bg-neutral-800 text-white hover:bg-neutral-700";
  const sizeClass =
    size === "large"
      ? "px-4 py-2 text-base"
      : size === "small"
        ? "px-2 py-1 text-xs"
        : "px-3 py-1.5 text-sm";
  return (
    <button
      type="button"
      {...props}
      className={cn(
        "inline-flex items-center justify-center gap-2 rounded-md font-medium transition-colors disabled:opacity-50",
        variantClass,
        sizeClass,
        className,
      )}
    >
      {children}
    </button>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Text
// ─────────────────────────────────────────────────────────────────────────────

export function Text({
  variant,
  color,
  truncate,
  className,
  title,
  children,
}: {
  variant?: "regular" | "small" | "small-strong" | "strong" | "large-strong";
  color?: "primary" | "secondary" | "tertiary" | "accent" | "support-green" | "support-orange" | "support-red" | "red" | "green" | "orange";
  truncate?: boolean;
  className?: string;
  title?: string;
  children?: React.ReactNode;
}) {
  const colorClass =
    color === "accent"
      ? "text-accent"
      : color === "secondary"
        ? "text-secondary"
        : color === "tertiary"
          ? "text-tertiary"
          : color === "support-green" || color === "green"
            ? "text-support-green"
            : color === "support-orange" || color === "orange"
              ? "text-support-orange"
              : color === "support-red" || color === "red"
                ? "text-support-red"
                : "text-primary";
  const sizeClass =
    variant === "small"
      ? "text-xs"
      : variant === "small-strong"
        ? "text-xs font-semibold"
        : variant === "strong"
          ? "font-semibold"
          : variant === "large-strong"
            ? "text-lg font-semibold"
            : "text-sm";
  const truncateClass = truncate ? "truncate" : "";
  return <span title={title} className={cn(colorClass, sizeClass, truncateClass, className)}>{children}</span>;
}

// ─────────────────────────────────────────────────────────────────────────────
// Badge
// ─────────────────────────────────────────────────────────────────────────────

export function Badge({
  color,
  size,
  className,
  children,
}: {
  color?: "green" | "orange" | "secondary" | "red";
  size?: "small" | "medium";
  className?: string;
  children?: React.ReactNode;
}) {
  const colorClass =
    color === "green"
      ? "bg-green-900/50 text-green-200"
      : color === "orange"
        ? "bg-orange-900/50 text-orange-200"
        : color === "red"
          ? "bg-red-900/50 text-red-200"
          : "bg-neutral-800 text-neutral-300";
  const sizeClass = size === "small" ? "px-1.5 py-0.5 text-[10px]" : "px-2 py-1 text-xs";
  return (
    <span className={cn("inline-flex items-center rounded-full font-medium", colorClass, sizeClass, className)}>
      {children}
    </span>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// EmptyState
// ─────────────────────────────────────────────────────────────────────────────

export function EmptyState({
  placement,
  title,
  description,
  className,
  children,
}: {
  placement?: "center" | "default" | "inline";
  title?: string;
  description?: string;
  className?: string;
  children?: React.ReactNode;
}) {
  const align =
    placement === "center"
      ? "items-center justify-center text-center"
      : placement === "inline"
        ? "items-center gap-2 flex-row"
        : "";
  return (
    <div className={cn("flex flex-col p-4", align, className)}>
      {title && <EmptyStateTitle>{title}</EmptyStateTitle>}
      {description && <EmptyStateDescription>{description}</EmptyStateDescription>}
      {children}
    </div>
  );
}

export function EmptyStateTitle({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <h3 className={cn("text-lg font-medium", className)}>{children}</h3>;
}

export function EmptyStateDescription({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <p className={cn("text-sm text-neutral-400", className)}>{children}</p>;
}

export function EmptyStateActions({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <div className={cn("mt-4 flex items-center gap-2", className)}>{children}</div>;
}

export function EmptyStateMedia({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <div className={cn("mb-4", className)}>{children}</div>;
}

// ─────────────────────────────────────────────────────────────────────────────
// Callout
// ─────────────────────────────────────────────────────────────────────────────

type CalloutProps = {
  color?: "green" | "orange" | "red" | "secondary";
  icon?: React.ReactNode;
  className?: string;
  children?: React.ReactNode;
};

export function Callout({ color, icon, className, children }: CalloutProps) {
  const colorClass =
    color === "green"
      ? "border-green-700/50 bg-green-950/30 text-green-200"
      : color === "orange"
        ? "border-orange-700/50 bg-orange-950/30 text-orange-200"
        : color === "red"
          ? "border-red-700/50 bg-red-950/30 text-red-200"
          : "border-neutral-700 bg-neutral-900 text-neutral-300";
  return (
    <div
      className={cn(
        "flex items-start gap-3 rounded-lg border p-3 text-sm",
        colorClass,
        className,
      )}
    >
      {icon && <div className="shrink-0">{icon}</div>}
      <div className="flex-1">{children}</div>
    </div>
  );
}

Callout.Text = Text;

// ─────────────────────────────────────────────────────────────────────────────
// Switch
// ─────────────────────────────────────────────────────────────────────────────

export function Switch({
  checked,
  onCheckedChange,
  disabled,
  className,
  children,
}: {
  checked?: boolean;
  onCheckedChange?: (checked: boolean) => void;
  disabled?: boolean;
  className?: string;
  children?: React.ReactNode;
}) {
  return (
    <label className={cn("inline-flex cursor-pointer items-center gap-2", className)}>
      <input
        type="checkbox"
        checked={checked}
        disabled={disabled}
        onChange={(e) => onCheckedChange?.(e.target.checked)}
        className="accent-accent"
      />
      {children}
    </label>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Table
// ─────────────────────────────────────────────────────────────────────────────

export function Table({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <table className={cn("w-full text-left text-sm", className)}>{children}</table>;
}

export function TableHeader({
  sticky,
  className,
  children,
}: {
  sticky?: boolean;
  className?: string;
  children?: React.ReactNode;
}) {
  return (
    <thead
      className={cn(
        "bg-neutral-900 text-neutral-400",
        sticky ? "sticky top-0 z-10" : "",
        className,
      )}
    >
      {children}
    </thead>
  );
}

export function TableBody({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <tbody className={className}>{children}</tbody>;
}

export function TableRow({
  onClick,
  className,
  children,
}: {
  onClick?: () => void;
  className?: string;
  children?: React.ReactNode;
}) {
  return (
    <tr onClick={onClick} className={cn("border-b border-neutral-800", onClick ? "cursor-pointer" : "", className)}>
      {children}
    </tr>
  );
}

export function TableHead({
  onClick,
  className,
  children,
}: {
  onClick?: () => void;
  className?: string;
  children?: React.ReactNode;
}) {
  return (
    <th onClick={onClick} className={cn("p-2 font-medium", onClick ? "cursor-pointer" : "", className)}>
      {children}
    </th>
  );
}

export function TableCell({
  onClick,
  colSpan,
  className,
  children,
}: {
  onClick?: () => void;
  colSpan?: number;
  className?: string;
  children?: React.ReactNode;
}) {
  return (
    <td onClick={onClick} colSpan={colSpan} className={cn("p-2", onClick ? "cursor-pointer" : "", className)}>
      {children}
    </td>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog
// ─────────────────────────────────────────────────────────────────────────────

export function Dialog({
  open,
  onOpenChange,
  title,
  description,
  size,
  showOverlay,
  className,
  children,
}: {
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
  title?: string;
  description?: string;
  size?: "small" | "medium" | "large";
  showOverlay?: boolean;
  className?: string;
  children?: React.ReactNode;
}) {
  if (!open) return null;
  const sizeClass =
    size === "large" ? "max-w-2xl" : size === "small" ? "max-w-sm" : "max-w-lg";
  return (
    <div
      className={cn(
        "fixed inset-0 z-50 flex items-center justify-center",
        showOverlay ? "bg-black/60" : "bg-black/40",
      )}
      onClick={() => onOpenChange?.(false)}
    >
      <div
        className={cn(
          "w-full rounded-lg border border-neutral-700 bg-neutral-900 p-4 shadow-2xl",
          sizeClass,
          className,
        )}
        onClick={(e) => e.stopPropagation()}
      >
        {title && <h2 className="text-lg font-semibold text-white">{title}</h2>}
        {description && <p className="mb-4 text-sm text-neutral-400">{description}</p>}
        <div>{children}</div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Select
// ─────────────────────────────────────────────────────────────────────────────

type SelectContextValue = {
  value?: string;
  onValueChange?: (value: string) => void;
  open: boolean;
  setOpen: (open: boolean) => void;
};

const SelectContext = createContext<SelectContextValue>({
  value: undefined,
  onValueChange: undefined,
  open: false,
  setOpen: () => {},
});

function useSelect() {
  return useContext(SelectContext);
}

export function Select({
  value,
  onValueChange,
  className,
  children,
}: {
  value?: string;
  onValueChange?: (value: string) => void;
  className?: string;
  children?: React.ReactNode;
}) {
  const [open, setOpen] = useState(false);
  return (
    <SelectContext.Provider value={{ value, onValueChange, open, setOpen }}>
      <div className={cn("relative inline-block w-full", className)}>{children}</div>
    </SelectContext.Provider>
  );
}

export function SelectTrigger({
  variant: _variant,
  size: _size,
  className,
  children,
}: {
  variant?: string;
  size?: string;
  className?: string;
  children?: React.ReactNode;
}) {
  const ctx = useSelect();
  return (
    <button
      type="button"
      onClick={() => ctx.setOpen(!ctx.open)}
      className={cn(
        "flex w-full items-center justify-between rounded-md border border-neutral-700 bg-neutral-900 px-3 py-1.5 text-sm text-white",
        className,
      )}
    >
      {children}
    </button>
  );
}

export function SelectValue({
  placeholder,
  className,
}: {
  placeholder?: string;
  className?: string;
}) {
  const ctx = useSelect();
  return (
    <span className={cn("text-neutral-300", ctx.value ? "text-white" : "", className)}>
      {ctx.value || placeholder}
    </span>
  );
}

export function SelectContent({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  const ctx = useSelect();
  if (!ctx.open) return null;
  return (
    <div
      className={cn(
        "absolute z-20 mt-1 w-full rounded-md border border-neutral-700 bg-neutral-900 shadow-xl",
        className,
      )}
    >
      {children}
    </div>
  );
}

export function SelectItem({
  value,
  sublabel,
  className,
  children,
}: {
  value: string;
  sublabel?: string;
  className?: string;
  children?: React.ReactNode;
}) {
  const ctx = useSelect();
  const label = `${children ?? ""}${sublabel ? ` — ${sublabel}` : ""}`;
  return (
    <div
      role="option"
      aria-selected={ctx.value === value}
      onClick={() => {
        ctx.onValueChange?.(value);
        ctx.setOpen(false);
      }}
      className={cn(
        "cursor-pointer px-3 py-1.5 text-sm text-neutral-300 hover:bg-neutral-800",
        ctx.value === value ? "bg-neutral-800 text-white" : "",
        className,
      )}
    >
      {label}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Field
// ─────────────────────────────────────────────────────────────────────────────

export function FieldSet({
  title,
  className,
  children,
}: {
  title?: string;
  className?: string;
  children?: React.ReactNode;
}) {
  return (
    <fieldset className={cn("rounded-lg border border-neutral-700 p-3", className)}>
      {title && <legend className="px-1 text-sm font-medium text-accent">{title}</legend>}
      {children}
    </fieldset>
  );
}

export function FieldGroup({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <div className={cn("flex flex-col gap-3", className)}>{children}</div>;
}

export function Field({
  label,
  description,
  orientation,
  className,
  children,
}: {
  label?: string;
  description?: string;
  orientation?: "horizontal" | "vertical";
  className?: string;
  children?: React.ReactNode;
}) {
  const dir = orientation === "horizontal" ? "flex-row items-center gap-4" : "flex-col gap-1";
  return (
    <div className={cn("flex", dir, className)}>
      {(label || description) && (
        <div>
          {label && <div className="text-sm font-medium text-white">{label}</div>}
          {description && <div className="text-xs text-neutral-500">{description}</div>}
        </div>
      )}
      {children}
    </div>
  );
}

export function FieldContent({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return <div className={cn("flex-1", className)}>{children}</div>;
}

export function FieldLabel({
  className,
  htmlFor,
  children,
}: {
  className?: string;
  htmlFor?: string;
  children?: React.ReactNode;
}) {
  return <label htmlFor={htmlFor} className={cn("text-sm font-medium text-white", className)}>{children}</label>;
}

export function Input({
  className,
  ...props
}: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={cn(
        "rounded-md border border-neutral-700 bg-neutral-900 px-3 py-1.5 text-sm text-white placeholder:text-neutral-500 focus:border-accent focus:outline-none",
        className,
      )}
    />
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Label
// ─────────────────────────────────────────────────────────────────────────────

export function Label({
  htmlFor,
  className,
  children,
}: {
  htmlFor?: string;
  className?: string;
  children?: React.ReactNode;
}) {
  return (
    <label htmlFor={htmlFor} className={cn("text-sm text-neutral-300", className)}>
      {children}
    </label>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// RadioGroup
// ─────────────────────────────────────────────────────────────────────────────

type RadioGroupContextValue = {
  value?: string;
  onValueChange?: (value: string) => void;
};

const RadioGroupContext = createContext<RadioGroupContextValue>({
  value: undefined,
  onValueChange: undefined,
});

function useRadioGroup() {
  return useContext(RadioGroupContext);
}

export function RadioGroup({
  value,
  onValueChange,
  orientation,
  className,
  children,
}: {
  value?: string;
  onValueChange?: (value: string) => void;
  orientation?: "horizontal" | "vertical";
  className?: string;
  children?: React.ReactNode;
}) {
  return (
    <RadioGroupContext.Provider value={{ value, onValueChange }}>
      <div
        className={cn(
          "flex gap-2",
          orientation === "horizontal" ? "flex-row" : "flex-col",
          className,
        )}
      >
        {children}
      </div>
    </RadioGroupContext.Provider>
  );
}

export function RadioGroupItem({
  value,
  id,
  className,
}: {
  value: string;
  id?: string;
  className?: string;
}) {
  const ctx = useRadioGroup();
  const generatedId = useId();
  const itemId = id ?? generatedId;
  return (
    <input
      id={itemId}
      type="radio"
      value={value}
      checked={ctx.value === value}
      onChange={() => ctx.onValueChange?.(value)}
      className={cn("accent-accent", className)}
    />
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ToggleButton
// ─────────────────────────────────────────────────────────────────────────────

export function ToggleButton({
  pressed,
  onPressedChange,
  variant,
  size,
  radius,
  className,
  children,
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & {
  pressed?: boolean;
  onPressedChange?: (pressed: boolean) => void;
  variant?: "filled" | "outline";
  size?: "small" | "medium";
  radius?: "full" | "default";
}) {
  const active = pressed
    ? "bg-accent-20 border-accent text-accent"
    : "bg-neutral-900 border-neutral-700 text-neutral-300";
  const sizeClass = size === "small" ? "px-2 py-1 text-xs" : "px-2.5 py-1 text-sm";
  const radiusClass = radius === "full" ? "rounded-full" : "rounded-md";
  return (
    <button
      type="button"
      aria-pressed={pressed}
      onClick={() => onPressedChange?.(!pressed)}
      className={cn(
        "border font-medium transition-colors",
        active,
        sizeClass,
        radiusClass,
        className,
      )}
      {...props}
    >
      {children}
    </button>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// NativeDatePicker
// ─────────────────────────────────────────────────────────────────────────────

type DatePickerContextValue = {
  value?: string;
  onValueChange?: (value: string) => void;
  type?: "date" | "time" | "dateAndTime";
};

const DatePickerContext = createContext<DatePickerContextValue>({
  value: undefined,
  onValueChange: undefined,
  type: "dateAndTime",
});

function useDatePicker() {
  return useContext(DatePickerContext);
}

export function NativeDatePickerRoot({
  value,
  onValueChange,
  type,
  className,
  children,
}: {
  value?: string;
  onValueChange?: (value: string) => void;
  type?: "date" | "time" | "dateAndTime";
  className?: string;
  children?: React.ReactNode;
}) {
  const inputType = type === "dateAndTime" ? "datetime-local" : type ?? "date";
  return (
    <DatePickerContext.Provider value={{ value, onValueChange, type }}>
      <div className={cn("relative inline-flex w-full", className)}>
        {children}
        <input
          type={inputType}
          value={value}
          onChange={(e) => onValueChange?.(e.target.value)}
          className="absolute inset-0 opacity-0"
        />
      </div>
    </DatePickerContext.Provider>
  );
}

export function NativeDatePickerTrigger({
  className,
  children,
}: {
  className?: string;
  children?: React.ReactNode;
}) {
  return (
    <div
      className={cn(
        "flex w-full cursor-pointer items-center gap-2 rounded-md border border-neutral-700 bg-neutral-900 px-3 py-1.5 text-sm text-white",
        className,
      )}
    >
      {children}
    </div>
  );
}

export function NativeDatePickerValue({
  placeholder,
  className,
}: {
  placeholder?: string;
  className?: string;
}) {
  const ctx = useDatePicker();
  return (
    <span className={cn("text-neutral-300", ctx.value ? "text-white" : "", className)}>
      {ctx.value || placeholder}
    </span>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SegmentedControl
// ─────────────────────────────────────────────────────────────────────────────

type SegmentedControlContextValue = {
  value?: string;
  onValueChange?: (value: string) => void;
};

const SegmentedControlContext = createContext<SegmentedControlContextValue>({
  value: undefined,
  onValueChange: undefined,
});

function useSegmentedControl() {
  return useContext(SegmentedControlContext);
}

export function SegmentedControl({
  value,
  onValueChange,
  className,
  children,
  ...props
}: {
  value?: string;
  onValueChange?: (value: string) => void;
  className?: string;
  children?: React.ReactNode;
} & React.HTMLAttributes<HTMLDivElement>) {
  return (
    <SegmentedControlContext.Provider value={{ value, onValueChange }}>
      <div
        role="radiogroup"
        className={cn("inline-flex rounded-lg border border-neutral-700 bg-neutral-900 p-1", className)}
        {...props}
      >
        {children}
      </div>
    </SegmentedControlContext.Provider>
  );
}

export function SegmentedControlItem({
  value,
  className,
  children,
}: {
  value: string;
  className?: string;
  children?: React.ReactNode;
}) {
  const ctx = useSegmentedControl();
  const selected = ctx.value === value;
  return (
    <button
      type="button"
      role="radio"
      aria-checked={selected}
      onClick={() => ctx.onValueChange?.(value)}
      className={cn(
        "rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
        selected
          ? "bg-accent text-black"
          : "text-neutral-300 hover:bg-white/5",
        className,
      )}
    >
      {children}
    </button>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Toast
// ─────────────────────────────────────────────────────────────────────────────

function makeToast(level: string) {
  return (message: string, opts?: { description?: string }) => {
    const out = opts?.description ? `${message}: ${opts.description}` : message;
    if (level === "error") {
      console.error(`[toast ${level}]`, out);
    } else {
      console.log(`[toast ${level}]`, out);
    }
  };
}

export const toast = {
  success: makeToast("success"),
  error: makeToast("error"),
  info: makeToast("info"),
  warning: makeToast("warning"),
};

// Keep `toast` itself callable so `toast(...)` works if needed.
export default function toastFn(message: string, opts?: { description?: string; type?: string }) {
  console.log("[toast]", message, opts);
}
toastFn.success = toast.success;
toastFn.error = toast.error;
toastFn.info = toast.info;
toastFn.warning = toast.warning;

import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

export function previewContent(content: string): string {
  return content.replace(/#{1,3} /g, '').slice(0, 180);
}

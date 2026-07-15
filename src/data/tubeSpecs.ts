// TUBE 규격표 (출처: 260430_Spec Ban Dalam _ Arami Update.csv, 2026)
// 분류: Type 1(Standar) · Type 2(Heavy Duty) · Type 3(OTR·AGR) · Type 4(IND)
// article=품번, description=제품명, Weight(kg) Std·Min·Max, Lebar(mm)=폭, Tebal(mm)=두께
export interface TubeSpec {
  no: number;
  category: 'Type 1' | 'Type 2' | 'Type 3' | 'Type 4';
  article: string;     // 품번 (미지정 시 '')
  description: string; // 제품명 (미지정 시 '')
  size: string;
  valve: string;
  wStd: number | null;
  wMin: number | null;
  wMax: number | null;
  lebar: number | null;
  tebal: number | null;
  packaging: 'Sack' | 'Box';
  qty: number | null;
}

export const TUBE_SPECS: TubeSpec[] = [
  // ── Type 1 (Standar) ──
  { no: 1, category: 'Type 1', article: '', description: '', size: '500-10', valve: '', wStd: null, wMin: null, wMax: null, lebar: null, tebal: null, packaging: 'Sack', qty: 10 },
  { no: 2, category: 'Type 1', article: 'VA50012T13', description: 'ASC 5.00-12TR13', size: '500-12', valve: 'TR 13', wStd: 0.67, wMin: 0.64, wMax: 0.70, lebar: 160, tebal: 1.40, packaging: 'Sack', qty: 10 },
  { no: 3, category: 'Type 1', article: 'VA55013T13', description: 'ASC 5.50-13TR13', size: '550-13', valve: 'TR 13', wStd: 0.78, wMin: 0.74, wMax: 0.81, lebar: 175, tebal: 1.40, packaging: 'Sack', qty: 10 },
  { no: 4, category: 'Type 1', article: 'VA60014T13', description: 'ASC 6.00-14TR13', size: '600-14', valve: 'TR 13', wStd: 0.87, wMin: 0.83, wMax: 0.91, lebar: 176, tebal: 1.40, packaging: 'Sack', qty: 10 },
  { no: 5, category: 'Type 1', article: 'VA65014T13', description: 'ASC 6.50-14TR13', size: '650-14', valve: 'TR 13', wStd: 0.98, wMin: 0.93, wMax: 1.03, lebar: 200, tebal: 1.50, packaging: 'Sack', qty: 10 },
  { no: 6, category: 'Type 1', article: 'VA70015T75', description: 'ASC 7.00-15TR75A', size: '700-15', valve: 'TR75', wStd: 1.30, wMin: 1.24, wMax: 1.37, lebar: 200, tebal: 1.60, packaging: 'Sack', qty: 10 },
  { no: 7, category: 'Type 1', article: 'VA70016T75', description: 'ASC 7.00-16TR75A', size: '700-16', valve: 'TR75', wStd: 1.42, wMin: 1.35, wMax: 1.49, lebar: 200, tebal: 1.60, packaging: 'Sack', qty: 10 },
  { no: 8, category: 'Type 1', article: 'VA70016T177', description: 'ASC 7.00-16TR177A', size: '700-16', valve: 'TR177', wStd: 1.42, wMin: 1.35, wMax: 1.49, lebar: 200, tebal: 1.60, packaging: 'Sack', qty: 10 },
  { no: 9, category: 'Type 1', article: 'VA75016T75A', description: 'ASC 7.50-16TR75A', size: '750-16', valve: 'TR75', wStd: 1.50, wMin: 1.43, wMax: 1.58, lebar: 220, tebal: 1.60, packaging: 'Sack', qty: 10 },
  { no: 10, category: 'Type 1', article: 'VA75016T177', description: 'ASC 7.50-16TR177A', size: '750-16', valve: 'TR177', wStd: 1.50, wMin: 1.43, wMax: 1.58, lebar: 220, tebal: 1.60, packaging: 'Sack', qty: 10 },
  { no: 11, category: 'Type 1', article: '', description: '', size: '825-16', valve: 'TR75', wStd: 1.80, wMin: 1.71, wMax: 1.89, lebar: 246, tebal: 1.60, packaging: 'Sack', qty: 10 },
  { no: 12, category: 'Type 1', article: 'VA82516T177', description: 'ASC 8.25-16TR177A', size: '825-16', valve: 'TR177', wStd: 1.80, wMin: 1.71, wMax: 1.89, lebar: 246, tebal: 1.60, packaging: 'Sack', qty: 10 },
  { no: 13, category: 'Type 1', article: '', description: '', size: '825-20', valve: 'TR75', wStd: 2.15, wMin: 2.04, wMax: 2.26, lebar: 240, tebal: 1.90, packaging: 'Sack', qty: 10 },
  { no: 14, category: 'Type 1', article: 'VA82520T177A', description: 'ASC 8.25-20TR177A', size: '825-20', valve: 'TR177', wStd: 2.15, wMin: 2.04, wMax: 2.26, lebar: 240, tebal: 1.90, packaging: 'Sack', qty: 10 },
  { no: 15, category: 'Type 1', article: 'VA90020T78', description: 'ASC 9.00-20TR78', size: '900-20', valve: 'TR78', wStd: 2.81, wMin: 2.67, wMax: 2.95, lebar: 258, tebal: 2.00, packaging: 'Sack', qty: 10 },
  { no: 16, category: 'Type 1', article: 'VA100020T78', description: 'ASC 10.00-20TR78', size: '1000-20', valve: 'TR78', wStd: 3.48, wMin: 3.31, wMax: 3.65, lebar: 290, tebal: 2.20, packaging: 'Sack', qty: 10 },
  { no: 17, category: 'Type 1', article: 'VA110020T78', description: 'ASC 11.00-20TR78', size: '1100-20', valve: 'TR78', wStd: 3.71, wMin: 3.52, wMax: 3.90, lebar: 311, tebal: 2.20, packaging: 'Sack', qty: 10 },
  { no: 18, category: 'Type 1', article: 'VA120020T78', description: 'ASC 12.00-20TR78', size: '1200-20', valve: 'TR78', wStd: 4.00, wMin: 3.80, wMax: 4.20, lebar: 330, tebal: 2.25, packaging: 'Sack', qty: 10 },
  { no: 19, category: 'Type 1', article: 'VA120020T179', description: 'ASC 12.00R20TR179', size: '1200-20', valve: 'TR179', wStd: 4.00, wMin: 3.80, wMax: 4.20, lebar: 330, tebal: 2.25, packaging: 'Sack', qty: 10 },
  { no: 20, category: 'Type 1', article: 'VA120024T78', description: 'ASC 12.00R24TR78', size: '12.00-24', valve: 'TR78', wStd: 4.63, wMin: 4.39, wMax: 4.86, lebar: 330, tebal: 2.30, packaging: 'Sack', qty: 10 },
  { no: 21, category: 'Type 1', article: 'VA131424T78', description: 'ASC 13.00/14.00R24 TR78', size: '13.00/1.400-24', valve: 'TR78', wStd: 5.40, wMin: 5.13, wMax: 5.67, lebar: 340, tebal: 2.40, packaging: 'Box', qty: 4 },
  { no: 22, category: 'Type 1', article: 'VA131424T179', description: 'ASC 13.00/14.00R24TR179', size: '13.00/1.400-24', valve: 'TR 179', wStd: 5.40, wMin: 5.13, wMax: 5.67, lebar: 340, tebal: 2.40, packaging: 'Box', qty: 4 },
  // ── Type 2 (Heavy Duty) ──
  { no: 23, category: 'Type 2', article: 'VA75016T177S', description: 'ASC 7.50-16TR177A Heavy Duty', size: '750-16', valve: 'TR177', wStd: 1.95, wMin: 1.85, wMax: 2.05, lebar: 220, tebal: 2.10, packaging: 'Box', qty: 9 },
  { no: 24, category: 'Type 2', article: 'VA82516T177S', description: 'ASC 8.25-16TR177A Heavy Duty', size: '825-16', valve: 'TR177', wStd: 2.34, wMin: 2.22, wMax: 2.46, lebar: 246, tebal: 2.10, packaging: 'Box', qty: 9 },
  { no: 25, category: 'Type 2', article: 'VA82520T78S', description: 'ASC 8.25-20TR78 Heavy Duty', size: '825-20', valve: 'TR78', wStd: 2.99, wMin: 2.84, wMax: 3.14, lebar: 245, tebal: 2.20, packaging: 'Box', qty: 6 },
  { no: 26, category: 'Type 2', article: 'VA90020T78S', description: 'ASC 9.00-20TR78 Heavy Duty', size: '900-20', valve: 'TR78', wStd: 3.65, wMin: 3.47, wMax: 3.84, lebar: 258, tebal: 2.65, packaging: 'Box', qty: 6 },
  { no: 27, category: 'Type 2', article: 'VA100020T78S', description: 'ASC 10.00-20TR78 Heavy Duty', size: '1000-20', valve: 'TR78', wStd: 4.52, wMin: 4.30, wMax: 4.75, lebar: 280, tebal: 3.00, packaging: 'Box', qty: 5 },
  { no: 28, category: 'Type 2', article: 'VA110020T78S', description: 'ASC 11.00-20TR78 Heavy Duty', size: '1100-20', valve: 'TR78', wStd: 4.97, wMin: 4.72, wMax: 5.22, lebar: 306, tebal: 3.00, packaging: 'Box', qty: 4 },
  { no: 29, category: 'Type 2', article: 'VA120020T78S', description: 'ASC 12.00-20TR78 Heavy Duty', size: '1200-20', valve: 'TR78', wStd: 5.07, wMin: 4.82, wMax: 5.32, lebar: 315, tebal: 3.00, packaging: 'Box', qty: 4 },
  { no: 30, category: 'Type 2', article: 'VA120020T179S', description: 'ASC 12.00R20TR179 Heavy Duty', size: '1200-20', valve: 'TR179', wStd: 5.07, wMin: 4.82, wMax: 5.32, lebar: 315, tebal: 3.00, packaging: 'Box', qty: 4 },
  { no: 31, category: 'Type 2', article: 'VA120024TR78HD', description: 'ASC 12.00R24TR78 Heavy Duty', size: '12.00-24', valve: 'TR78', wStd: 5.73, wMin: 5.44, wMax: 6.01, lebar: 310, tebal: 3.00, packaging: 'Box', qty: 4 },
  { no: 32, category: 'Type 2', article: 'VA131424T78S', description: 'ASC 13.00/14.00R24 TR78 Heavy Duty', size: '13.00/1.400-24', valve: 'TR78', wStd: 6.50, wMin: 6.18, wMax: 6.83, lebar: 340, tebal: 2.75, packaging: 'Box', qty: 4 },
  { no: 33, category: 'Type 2', article: 'VA140025T179S', description: 'ASC 14.00-25TR179 Heavy Duty', size: '14.00-25', valve: 'TR179', wStd: 5.85, wMin: 5.56, wMax: 6.14, lebar: 380, tebal: 2.40, packaging: 'Box', qty: 3 },
  { no: 34, category: 'Type 2', article: 'VA160025T179S', description: 'ASC 16.00-25TR179 Heavy Duty', size: '16.00-25', valve: 'TR179', wStd: 7.50, wMin: 7.13, wMax: 7.88, lebar: 460, tebal: 2.40, packaging: 'Box', qty: 3 },
  // ── Type 3 (OTR·AGR) ──
  { no: 35, category: 'Type 3', article: 'VA12165T15', description: 'ASC 12-16.5TR15', size: '12-16.5', valve: 'TR15', wStd: 2.00, wMin: 1.90, wMax: 2.10, lebar: 285, tebal: 2.00, packaging: 'Box', qty: null },
  { no: 36, category: 'Type 3', article: 'VA1258018T218', description: 'ASC 12.5/80-18TR218', size: '12.5/80-18', valve: 'TR218', wStd: 2.38, wMin: 2.26, wMax: 2.50, lebar: 320, tebal: 1.60, packaging: 'Box', qty: 10 },
  { no: 37, category: 'Type 3', article: 'VA140020T78', description: 'ASC 14.00-20TR78', size: '14.00-20', valve: 'TR78', wStd: 4.53, wMin: 4.30, wMax: 4.76, lebar: 380, tebal: 2.00, packaging: 'Box', qty: 5 },
  { no: 38, category: 'Type 3', article: 'VA12424T218', description: 'ASC 12.4-24TR218', size: '12.4-24', valve: 'TR218', wStd: 4.10, wMin: 3.90, wMax: 4.31, lebar: 350, tebal: 1.90, packaging: 'Box', qty: 6 },
  { no: 39, category: 'Type 3', article: 'VA16924T218', description: 'ASC 16.9-24TR218', size: '16.9-24', valve: 'TR218', wStd: 4.96, wMin: 4.71, wMax: 5.20, lebar: 405, tebal: 2.00, packaging: 'Box', qty: 5 },
  { no: 40, category: 'Type 3', article: 'VA140025T179', description: 'ASC 14.00-25TR179', size: '14.00-25', valve: 'TR179', wStd: 4.76, wMin: 4.52, wMax: 5.00, lebar: 380, tebal: 1.80, packaging: 'Box', qty: 5 },
  { no: 41, category: 'Type 3', article: 'VA15525T179', description: 'ASC 15.5-25TR179', size: '15.5-25', valve: 'TR179', wStd: 4.76, wMin: 4.52, wMax: 5.00, lebar: 380, tebal: 1.80, packaging: 'Box', qty: 5 },
  { no: 42, category: 'Type 3', article: 'VA160025T179', description: 'ASC 16.00-25TR179', size: '16.00-25', valve: 'TR179', wStd: 6.63, wMin: 6.30, wMax: 6.96, lebar: 460, tebal: 2.00, packaging: 'Box', qty: 3 },
  { no: 43, category: 'Type 3', article: 'VA17525T1175', description: 'ASC 17.5-25TRJ1175C', size: '17.5-25', valve: 'TRJ1175C', wStd: 6.63, wMin: 6.30, wMax: 6.96, lebar: 460, tebal: 2.00, packaging: 'Box', qty: 3 },
  { no: 44, category: 'Type 3', article: 'VA17525T179', description: 'ASC 17.5-25TR179', size: '17.5-25', valve: 'TR179', wStd: 6.63, wMin: 6.30, wMax: 6.96, lebar: 460, tebal: 2.00, packaging: 'Box', qty: 3 },
  { no: 45, category: 'Type 3', article: 'VA180025T179', description: 'ASC 18.00-25TR179', size: '18.00-25', valve: 'TR179', wStd: 9.50, wMin: 9.03, wMax: 9.98, lebar: 545, tebal: 2.50, packaging: 'Box', qty: 2 },
  { no: 46, category: 'Type 3', article: 'VA20525T1175', description: 'ASC 20.5-25TRJ1175C', size: '20.5-25', valve: 'TRJ1175C', wStd: 9.50, wMin: 9.03, wMax: 9.98, lebar: 545, tebal: 2.50, packaging: 'Box', qty: 2 },
  { no: 47, category: 'Type 3', article: 'VA20525T179', description: 'ASC 20.5-25TR179', size: '20.5-25', valve: 'TR179', wStd: 9.50, wMin: 9.03, wMax: 9.98, lebar: 545, tebal: 2.50, packaging: 'Box', qty: 2 },
  { no: 48, category: 'Type 3', article: 'VA23525T1175', description: 'ASC 23.5-25TRJ1175C', size: '23.5-25', valve: 'TRJ1175C', wStd: 11.00, wMin: 10.45, wMax: 11.55, lebar: 615, tebal: 2.30, packaging: 'Box', qty: 2 },
  { no: 49, category: 'Type 3', article: 'VA23525T179', description: 'ASC 23.5-25TR179', size: '23.5-25', valve: 'TR179', wStd: 11.00, wMin: 10.45, wMax: 11.55, lebar: 615, tebal: 2.30, packaging: 'Box', qty: 2 },
  { no: 50, category: 'Type 3', article: 'VA16928T218', description: 'ASC 16.9-28TR218', size: '16.9-28', valve: 'TR218', wStd: 6.10, wMin: 5.80, wMax: 6.41, lebar: 440, tebal: 1.60, packaging: 'Box', qty: 4 },
  { no: 51, category: 'Type 3', article: 'VA16928T220', description: 'ASC 16.9-28TR220', size: '16.9-28', valve: 'TR220', wStd: 6.10, wMin: 5.80, wMax: 6.41, lebar: 440, tebal: 1.60, packaging: 'Box', qty: 4 },
  { no: 52, category: 'Type 3', article: 'VA18430T218', description: 'ASC 18.4-30TR218', size: '18.4-30', valve: 'TR218', wStd: 6.90, wMin: 6.56, wMax: 7.25, lebar: 468, tebal: 1.90, packaging: 'Box', qty: 3 },
  { no: 53, category: 'Type 3', article: 'VA18434T218', description: 'ASC 18.4-34TR218', size: '18.4-34', valve: 'TR218', wStd: 7.32, wMin: 6.95, wMax: 7.69, lebar: 465, tebal: 1.90, packaging: 'Box', qty: 3 },
  { no: 54, category: 'Type 3', article: 'VA816T13', description: 'ASC 8-16TR13', size: '8-16', valve: 'TR13', wStd: 1.00, wMin: 0.95, wMax: 1.05, lebar: 195, tebal: 1.30, packaging: 'Box', qty: 15 },
  { no: 55, category: 'Type 3', article: 'VA818T13', description: 'ASC 8-18TR15', size: '8-18', valve: 'TR15', wStd: 1.60, wMin: 1.52, wMax: 1.68, lebar: 213, tebal: 1.70, packaging: 'Box', qty: 15 },
  { no: 56, category: 'Type 3', article: 'VA167020T75', description: 'ASC 16.0/70-20TR75', size: '16.0/70-20', valve: 'TR75', wStd: 4.53, wMin: 4.30, wMax: 4.76, lebar: 400, tebal: 2.00, packaging: 'Box', qty: 4 },
  { no: 57, category: 'Type 3', article: 'VA83824T218', description: 'ASC 8.3/8-24TR218', size: '8.3/8-24', valve: 'TR218', wStd: 1.90, wMin: 1.81, wMax: 2.00, lebar: 230, tebal: 1.50, packaging: 'Box', qty: 10 },
  { no: 58, category: 'Type 3', article: 'VA93924T218', description: 'ASC 9.3/9-24TR218', size: '9.3/9-24', valve: 'TR218', wStd: 2.50, wMin: 2.38, wMax: 2.63, lebar: 240, tebal: 1.70, packaging: 'Box', qty: 10 },
  { no: 59, category: 'Type 3', article: 'VA11224T218', description: 'ASC 11.2-24TR218', size: '11.2 - 24', valve: 'TR218', wStd: 4.00, wMin: 3.80, wMax: 4.20, lebar: 315, tebal: 1.70, packaging: 'Box', qty: 6 },
  { no: 60, category: 'Type 3', article: 'VA149247218', description: 'ASC 14.9-24TR218', size: '14.9-24', valve: 'TR218', wStd: 4.96, wMin: 4.71, wMax: 5.20, lebar: 405, tebal: 2.00, packaging: 'Box', qty: 4 },
  { no: 61, category: 'Type 3', article: 'VA13614926T218', description: 'ASC 13.6/14.9-26TR218', size: '13.6/14.9-26', valve: 'TR218', wStd: 4.24, wMin: 4.03, wMax: 4.45, lebar: 345, tebal: 1.80, packaging: 'Box', qty: 4 },
  { no: 62, category: 'Type 3', article: 'VA13614928T218', description: 'ASC 13.6/14.9-28TR218', size: '13.6/14.9-28', valve: 'TR218', wStd: 4.85, wMin: 4.61, wMax: 5.09, lebar: 398, tebal: 1.70, packaging: 'Box', qty: 4 },
  { no: 63, category: 'Type 3', article: 'VA4006011555T', description: 'ASC 4.00/60-15.5TR15', size: '4.00/60-15.5', valve: 'TR15', wStd: 3.24, wMin: 3.07, wMax: 3.40, lebar: 370, tebal: 1.90, packaging: 'Box', qty: 6 },
  { no: 64, category: 'Type 3', article: 'VA160020T78', description: 'ASC 16.00-20TR78', size: '16.00-20', valve: 'TR78', wStd: 5.45, wMin: 5.18, wMax: 5.72, lebar: 395, tebal: 2.30, packaging: 'Box', qty: 3 },
  { no: 65, category: 'Type 3', article: 'VA12165T15', description: 'ASC 12-16.5TR15', size: '12-16.5', valve: 'TR15', wStd: 1.99, wMin: 1.89, wMax: 2.08, lebar: 290, tebal: 1.67, packaging: 'Box', qty: 12 },
  { no: 66, category: 'Type 3', article: 'VA1058018T15', description: 'ASC 10.5/80-18TR15', size: '10.5/80-18', valve: 'TR15', wStd: 2.12, wMin: 2.01, wMax: 2.23, lebar: 280, tebal: 1.57, packaging: 'Box', qty: 10 },
  { no: 67, category: 'Type 3', article: 'VA19524TR218', description: 'ASC 19.5-24TR218', size: '19.5-24', valve: 'TR218', wStd: 4.96, wMin: 4.71, wMax: 5.20, lebar: 405, tebal: 2.00, packaging: 'Box', qty: 4 },
  { no: 68, category: 'Type 3', article: 'VA23126T179', description: 'ASC 23.1-26TR179', size: '23.1-26', valve: 'TR179', wStd: 11.90, wMin: 11.30, wMax: 12.50, lebar: 625, tebal: 2.50, packaging: 'Box', qty: 2 },
  { no: 69, category: 'Type 3', article: 'VA23126T218', description: 'ASC 23.1-26TR218', size: '23.1-26', valve: 'TR218', wStd: 11.90, wMin: 11.30, wMax: 12.50, lebar: 625, tebal: 2.50, packaging: 'Box', qty: 2 },
  { no: 70, category: 'Type 3', article: 'VA1241128T218', description: 'ASC 12.4/11-28TR218', size: '12.4/11-28', valve: 'TR218', wStd: 3.85, wMin: 3.66, wMax: 4.04, lebar: 310, tebal: 1.78, packaging: 'Box', qty: 4 },
  // ── Type 4 (IND) ──
  { no: 71, category: 'Type 4', article: 'VA18708J2', description: 'ASC 18*7-8JS2', size: '18x7-8', valve: 'JS2', wStd: 0.45, wMin: 0.43, wMax: 0.47, lebar: 150, tebal: 1.40, packaging: 'Sack', qty: 10 },
  { no: 72, category: 'Type 4', article: 'VA60009J2', description: 'ASC 6.00-9JS2', size: '6.00-9', valve: 'JS2', wStd: 0.62, wMin: 0.59, wMax: 0.65, lebar: 150, tebal: 1.60, packaging: 'Sack', qty: 30 },
  { no: 73, category: 'Type 4', article: 'VA2189J2', description: 'ASC 21*8-9JS2', size: '21X8-9', valve: 'JS2', wStd: 0.62, wMin: 0.59, wMax: 0.65, lebar: 150, tebal: 1.60, packaging: 'Sack', qty: 10 },
  { no: 74, category: 'Type 4', article: 'VA65010J2', description: 'ASC 6.50-10JS2', size: '6.50-10', valve: 'JS2', wStd: 0.71, wMin: 0.67, wMax: 0.74, lebar: 185, tebal: 1.40, packaging: 'Sack', qty: 30 },
  { no: 75, category: 'Type 4', article: '', description: '', size: '23x9-10', valve: 'JS2', wStd: 0.71, wMin: 0.67, wMax: 0.74, lebar: 185, tebal: 1.40, packaging: 'Sack', qty: 10 },
  { no: 76, category: 'Type 4', article: 'VA70012T75', description: 'ASC 7.00-12TR75', size: '7.00-12', valve: 'TR75', wStd: 0.93, wMin: 0.88, wMax: 0.98, lebar: 205, tebal: 1.60, packaging: 'Sack', qty: 18 },
  { no: 77, category: 'Type 4', article: 'VA60015T13', description: 'ASC 6.00-15TR13', size: '6.00-15', valve: 'TR13', wStd: 0.77, wMin: 0.73, wMax: 0.80, lebar: 165, tebal: 1.30, packaging: 'Sack', qty: 10 },
  { no: 78, category: 'Type 4', article: 'VA28915T77', description: 'ASC 28*9-15TR77', size: '28*9-15', valve: 'TR77', wStd: 1.28, wMin: 1.22, wMax: 1.34, lebar: 210, tebal: 1.60, packaging: 'Sack', qty: 15 },
  { no: 79, category: 'Type 4', article: 'VA30015T77', description: 'ASC 3.00-15TR77', size: '300-15', valve: 'TR77', wStd: 1.44, wMin: 1.36, wMax: 1.51, lebar: 245, tebal: 1.50, packaging: 'Sack', qty: 10 },
  { no: 80, category: 'Type 4', article: 'VA82515T77', description: 'ASC 8.25-15TR77', size: '8.25-15', valve: 'TR77', wStd: 1.44, wMin: 1.36, wMax: 1.51, lebar: 245, tebal: 1.50, packaging: 'Sack', qty: 15 },
];

//
//  TSQCalendarState.m
//  TimesSquare
//
//  Created by Jim Puls on 11/14/12.
//  Licensed to Square, Inc. under one or more contributor license agreements.
//  See the LICENSE file distributed with this work for the terms under
//  which Square, Inc. licenses this file to you.

#import "TSQCalendarView.h"
#import "TSQCalendarMonthHeaderCell.h"
#import "TSQCalendarRowCell.h"

@interface TSQCalendarView () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) TSQCalendarMonthHeaderCell *headerView; // nil unless pinsHeaderToTop == YES

@end


@implementation TSQCalendarView

const NSInteger headingOriginInset = 64;

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return nil;
    }
    
    [self _TSQCalendarView_commonInit];
    
    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }
    
    [self _TSQCalendarView_commonInit];
    
    return self;
}

- (void)_TSQCalendarView_commonInit;
{
    _tableView = [[UITableView alloc] initWithFrame:self.bounds style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    _selectionMode = TSQCalendarSelectionModeDay;
    [self addSubview:_tableView];
}

- (void)dealloc;
{
    _tableView.dataSource = nil;
    _tableView.delegate = nil;
}

- (NSCalendar *)calendar;
{
    if (!_calendar) {
        self.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    }
    return _calendar;
}

- (Class)headerCellClass;
{
    if (!_headerCellClass) {
        self.headerCellClass = [TSQCalendarMonthHeaderCell class];
    }
    return _headerCellClass;
}

- (Class)rowCellClass;
{
    if (!_rowCellClass) {
        self.rowCellClass = [TSQCalendarRowCell class];
    }
    return _rowCellClass;
}

- (Class)cellClassForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.row == 0 && !self.pinsHeaderToTop) {
        return [self headerCellClass];
    } else {
        return [self rowCellClass];
    }
}

- (void)setBackgroundColor:(UIColor *)backgroundColor;
{
    [super setBackgroundColor:backgroundColor];
    [self.tableView setBackgroundColor:backgroundColor];
}

- (void)setPinsHeaderToTop:(BOOL)pinsHeaderToTop;
{
    _pinsHeaderToTop = pinsHeaderToTop;
    [self setNeedsLayout];
}

- (void)setFirstDate:(NSDate *)firstDate;
{
    // clamp to the beginning of its month
    _firstDate = [self clampDate:firstDate toComponents:NSCalendarUnitMonth|NSCalendarUnitYear];
}

- (void)setLastDate:(NSDate *)lastDate;
{
    // clamp to the end of its month
    NSDate *firstOfMonth = [self clampDate:lastDate toComponents:NSCalendarUnitMonth|NSCalendarUnitYear];
    
    NSDateComponents *offsetComponents = [[NSDateComponents alloc] init];
    offsetComponents.month = 1;
    offsetComponents.day = -1;
    _lastDate = [self.calendar dateByAddingComponents:offsetComponents toDate:firstOfMonth options:0];
}

- (BOOL)isScrolling
{
    return (self.tableView.isDragging || self.tableView.isDecelerating);
    
}

- (void)scrollToDate:(NSDate *)date animated:(BOOL)animated;
{
    [self scrollToDate:date animated:animated atScrollPosition:UITableViewScrollPositionTop];
}

- (void)scrollToDate:(NSDate *)date animated:(BOOL)animated atScrollPosition:(UITableViewScrollPosition)scrollPosition;
{
    NSIndexPath *path;
    if (self.pinsHeaderToTop || self.pagingEnabled) {
        NSInteger section = [self sectionForDate:date];
        path = [NSIndexPath indexPathForRow:0 inSection:section];
    } else {
        path = [self indexPathForRowAtDate:date];
    }
    if (path) {
        [self.tableView scrollToRowAtIndexPath:path atScrollPosition:scrollPosition animated:animated];
    }
}

- (TSQCalendarMonthHeaderCell *)makeHeaderCellWithIdentifier:(NSString *)identifier;
{
    TSQCalendarMonthHeaderCell *cell = [[[self headerCellClass] alloc] initWithCalendar:self.calendar reuseIdentifier:identifier];
    cell.backgroundColor = self.backgroundColor;
    cell.calendarView = self;
    return cell;
}

#pragma mark Date selections

- (void)setSelectionMode:(TSQCalendarSelectionMode)selectionMode
{
    if (selectionMode == _selectionMode) return;
    TSQCalendarSelectionMode previousSelectionMode = _selectionMode;
    _selectionMode = selectionMode;
    
    if (previousSelectionMode == TSQCalendarSelectionModeDateRange) {
        NSDate *startDate = self.selectedStartDate;
        self.selectedStartDate = nil;
        self.selectedEndDate = nil;
        self.selectedDate = startDate;
    } else if (previousSelectionMode == TSQCalendarSelectionModeDay) {
        NSDate *selectedDate = self.selectedDate;
        self.selectedDate = nil;
        self.selectedStartDate = selectedDate;
    }
}

- (void)resetSelectedDates
{
    for (NSDate *date in _selectedDates) {
        [[self cellForRowAtDate:date] deselectColumnForDate:date];
    }
    _selectedDates = @[];
    _selectedDate = nil;
    _selectedStartDate = nil;
    _selectedEndDate = nil;
    
    if ([self.delegate respondsToSelector:@selector(resetSelectedDatesForCalendarView:)]) {
        [self.delegate resetSelectedDatesForCalendarView:self];
    }
}

- (void)resetSelectedDateRange
{
    for (NSDate *date in _selectedDates) {
        [[self cellForRowAtDate:date] deselectColumnForDate:date];
    }
    _selectedEndDate = nil;
    _selectedDates = _selectedStartDate ? @[_selectedStartDate] : @[];
    [[self cellForRowAtDate:_selectedStartDate] selectColumnForDate:_selectedStartDate];
}

- (void)setSelectedDate:(NSDate *)newSelectedDate;
{
    if (newSelectedDate == nil) {
        [self resetSelectedDates];
        return;
    }
    
    // clamp to beginning of its day
    NSDate *startOfDay = [self clampDate:newSelectedDate toComponents:NSDayCalendarUnit|NSMonthCalendarUnit|NSYearCalendarUnit];
    if ([self.delegate respondsToSelector:@selector(calendarView:shouldSelectDate:)] && ![self.delegate calendarView:self shouldSelectDate:startOfDay]) {
        return;
    }
    
    NSIndexPath *newIndexPath = [self indexPathForRowAtDate:startOfDay];
    CGRect newIndexPathRect = [self.tableView rectForRowAtIndexPath:newIndexPath];
    CGRect scrollBounds = self.tableView.bounds;
    if (self.pagingEnabled) {
        CGRect sectionRect = [self.tableView rectForSection:newIndexPath.section];
        [self.tableView setContentOffset:sectionRect.origin animated:YES];
    } else {
        if (CGRectGetMinY(scrollBounds) > CGRectGetMinY(newIndexPathRect)) {
            [self.tableView scrollToRowAtIndexPath:newIndexPath atScrollPosition:UITableViewScrollPositionTop animated:YES];
        } else if (CGRectGetMaxY(scrollBounds) < CGRectGetMaxY(newIndexPathRect)) {
            [self.tableView scrollToRowAtIndexPath:newIndexPath atScrollPosition:UITableViewScrollPositionBottom animated:YES];
        }
    }
    
    [self resetSelectedDates];
    _selectedDate = startOfDay;
    _selectedDates = @[_selectedDate];
    [self updateSelectedDates];
    
    if ([self.delegate respondsToSelector:@selector(calendarView:didSelectDate:)]) {
        [self.delegate calendarView:self didSelectDate:startOfDay];
    }
}

- (void)setSelectedStartDate:(NSDate *)newSelectedStartDate
{
    if (newSelectedStartDate == nil) {
        [self resetSelectedDates];
        if ([self.delegate respondsToSelector:@selector(calendarView:didSelectStartDate:)]) {
            [self.delegate calendarView:self didSelectStartDate:nil];
        }
        return;
    }
    
    NSDate *startOfDay = [self clampDate:newSelectedStartDate toComponents:NSDayCalendarUnit|NSMonthCalendarUnit|NSYearCalendarUnit];
    if ([self.delegate respondsToSelector:@selector(calendarView:shouldSelectDate:)] && ![self.delegate calendarView:self shouldSelectDate:startOfDay]) {
        return;
    }
    
    [self resetSelectedDates];
    _selectedStartDate = startOfDay;
    _selectedDates = @[startOfDay];
    [self updateSelectedDates];
    
    if ([self.delegate respondsToSelector:@selector(calendarView:didSelectStartDate:)]) {
        [self.delegate calendarView:self didSelectStartDate:startOfDay];
    }
}

- (void)setSelectedEndDate:(NSDate *)newSelectedEndDate
{
    if (newSelectedEndDate == nil) {
        [self resetSelectedDateRange];
        if ([self.delegate respondsToSelector:@selector(calendarView:didSelectEndDate:)]) {
            [self.delegate calendarView:self didSelectEndDate:nil];
        }
        return;
    }
    
    NSDate *startOfDay = [self clampDate:newSelectedEndDate toComponents:NSDayCalendarUnit|NSMonthCalendarUnit|NSYearCalendarUnit];
    if ([self.delegate respondsToSelector:@selector(calendarView:shouldSelectDate:)] && ![self.delegate calendarView:self shouldSelectDate:startOfDay]) {
        return;
    }
    
    [self resetSelectedDateRange];
    _selectedEndDate = startOfDay;
    _selectedDates = [self datesBetweenStart:_selectedStartDate AndEnd:startOfDay];
    [self updateSelectedDates];
    
    if ([self.delegate respondsToSelector:@selector(calendarView:didSelectEndDate:)]) {
        [self.delegate calendarView:self didSelectEndDate:startOfDay];
    }
}

- (void)setSelectionError:(TSQCalendarError *)selectionError
{
    _selectionError = selectionError;
    
    if (selectionError && [self.delegate respondsToSelector:@selector(calendarView:didFailToSelectDateWithError:)]) {
        [self.delegate calendarView:self didFailToSelectDateWithError:selectionError];
    }
}

- (void)updateSelectedDates
{
    for (NSDate *date in _selectedDates) {
        [[self cellForRowAtDate:date] selectColumnForDate:date];
    }
}

#pragma mark Calendar calculations

- (NSDate *)firstOfMonthForSection:(NSInteger)section;
{
    NSDateComponents *offset = [NSDateComponents new];
    offset.month = section;
    return [self.calendar dateByAddingComponents:offset toDate:self.firstDate options:0];
}

- (TSQCalendarRowCell *)cellForRowAtDate:(NSDate *)date;
{
    return (TSQCalendarRowCell *)[self.tableView cellForRowAtIndexPath:[self indexPathForRowAtDate:date]];
}

- (NSInteger)sectionForDate:(NSDate *)date;
{
    return [self.calendar components:NSCalendarUnitMonth fromDate:self.firstDate toDate:date options:0].month;
}

- (NSIndexPath *)indexPathForRowAtDate:(NSDate *)date;
{
    if (!date) {
        return nil;
    }
    
    NSInteger section = [self sectionForDate:date];
    NSDate *firstOfMonth = [self firstOfMonthForSection:section];
    NSInteger firstWeek = [self.calendar components:NSWeekOfMonthCalendarUnit fromDate:firstOfMonth].weekOfMonth;
    NSInteger targetWeek = [self.calendar components:NSWeekOfMonthCalendarUnit fromDate:date].weekOfMonth;

    return [NSIndexPath indexPathForRow:(self.pinsHeaderToTop ? 0 : 1) + targetWeek - firstWeek inSection:section];
}

- (NSArray *)datesBetweenStart:(NSDate *)start AndEnd:(NSDate *)end
{
    NSMutableArray *dates = [NSMutableArray array];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.day = 1;
    NSDate *current = start;
    while ([end compare:current] != NSOrderedAscending) {
        [dates addObject:current];
        NSDate *nextDay = [self.calendar dateByAddingComponents:components toDate:current options:0];
        current = [self clampDate:nextDay toComponents:NSCalendarUnitDay|NSCalendarUnitMonth|NSCalendarUnitYear];
    }
    return  dates;
}

#pragma mark UIView

- (void)layoutSubviews;
{
    [super layoutSubviews];
    if (self.pinsHeaderToTop) {
        if (!self.headerView) {
            self.headerView = [self makeHeaderCellWithIdentifier:nil];
            if (self.tableView.visibleCells.count > 0) {
                self.headerView.firstOfMonth = [self.tableView.visibleCells[0] firstOfMonth];
            } else {
                self.headerView.firstOfMonth = self.firstDate;
            }
            [self addSubview:self.headerView];
        }
        CGRect bounds = self.bounds;
        CGRect headerRect;
        CGRect tableRect;
        CGRectDivide(bounds, &headerRect, &tableRect, [[self headerCellClass] cellHeight], CGRectMinYEdge);
        self.headerView.frame = headerRect;
        self.tableView.frame = tableRect;
    } else {
        if (self.headerView) {
            [self.headerView removeFromSuperview];
            self.headerView = nil;
        }
        self.tableView.frame = self.bounds;
    }
}

#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return 1 + [self.calendar components:NSMonthCalendarUnit fromDate:self.firstDate toDate:self.lastDate options:0].month;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    NSDate *firstOfMonth = [self firstOfMonthForSection:section];
    NSRange rangeOfWeeks = [self.calendar rangeOfUnit:NSWeekCalendarUnit inUnit:NSMonthCalendarUnit forDate:firstOfMonth];
    return (self.pinsHeaderToTop ? 0 : 1) + rangeOfWeeks.length;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.row == 0 && !self.pinsHeaderToTop) {
        // month header
        static NSString *identifier = @"header";
        TSQCalendarMonthHeaderCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
        if (!cell) {
            cell = [self makeHeaderCellWithIdentifier:identifier];
        }
        return cell;
    } else {
        static NSString *identifier = @"row";
        TSQCalendarRowCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
        if (!cell) {
            cell = [[[self rowCellClass] alloc] initWithCalendar:self.calendar reuseIdentifier:identifier];
            cell.backgroundColor = self.backgroundColor;
            cell.calendarView = self;
        }
        return cell;
    }
}

#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath;
{
    NSDate *firstOfMonth = [self firstOfMonthForSection:indexPath.section];
    [(TSQCalendarCell *)cell setFirstOfMonth:firstOfMonth];
    if (indexPath.row > 0 || self.pinsHeaderToTop) {
        NSInteger ordinalityOfFirstDay = [self.calendar ordinalityOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitWeekOfMonth forDate:firstOfMonth];
        NSDateComponents *dateComponents = [NSDateComponents new];
        dateComponents.day = 1 - ordinalityOfFirstDay;
        dateComponents.week = indexPath.row - (self.pinsHeaderToTop ? 0 : 1);
        [(TSQCalendarRowCell *)cell setBeginningDate:[self.calendar dateByAddingComponents:dateComponents toDate:firstOfMonth options:0]];
        
        if (self.selectionMode == TSQCalendarSelectionModeDay) {
            [(TSQCalendarRowCell *)cell selectColumnForDate:self.selectedDate];
        } else {
            for (NSDate *date in _selectedDates) {
                [(TSQCalendarRowCell *)cell selectColumnForDate:date];
            }
        }
        
        BOOL isBottomRow = (indexPath.row == [self tableView:tableView numberOfRowsInSection:indexPath.section] - (self.pinsHeaderToTop ? 0 : 1));
        [(TSQCalendarRowCell *)cell setBottomRow:isBottomRow];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    return [[self cellClassForRowAtIndexPath:indexPath] cellHeight];
}

#pragma mark UIScrollViewDelegate

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset;
{
    if (self.pagingEnabled) {
        NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:*targetContentOffset];
        // If the target offset is at the third row or later, target the next month; otherwise, target the beginning of this month.
        NSInteger section = indexPath.section;
        if (indexPath.row > 2) {
            section++;
        }
        CGRect sectionRect = [self.tableView rectForSection:section];
        if (self.displayHeaderWhenPaging) {
            sectionRect.origin.y -= headingOriginInset;
        }
        *targetContentOffset = sectionRect.origin;
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView;
{
    if (self.pinsHeaderToTop && self.tableView.visibleCells.count > 0) {
        TSQCalendarCell *cell = self.tableView.visibleCells[0];
        self.headerView.firstOfMonth = cell.firstOfMonth;
    }
}

- (NSDate *)clampDate:(NSDate *)date toComponents:(NSUInteger)unitFlags
{
    NSDateComponents *components = [self.calendar components:unitFlags fromDate:date];
    return [self.calendar dateFromComponents:components];
}

@end
